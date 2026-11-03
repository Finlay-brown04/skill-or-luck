# =============================================================================
# 01_download_data.R
# Purpose: Download the Fama/French 3 Factors (monthly) CSV, keep the original unchanged in data/raw, record its source, and inspect the raw layout.
# =============================================================================

# 1. Settings
source_page <- "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/data_library.html"
file_url    <- "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_Factors_CSV.zip"
zip_path    <- "data/raw/F-F_Research_Data_Factors_CSV.zip"
meta_path   <- "data/raw/DATA_SOURCE.txt"

stopifnot(dir.exists("data/raw")) # Safety check

# 2. Download 
downloaded_now <- FALSE
if (!file.exists(zip_path)) {
  download.file(url = file_url, destfile = zip_path, mode = "wb")  #wb means write binary
  downloaded_now <- TRUE
  download_time  <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
}
stopifnot(file.exists(zip_path))

#3. Extract the CSV, finding its name automatically
zip_contents <- unzip(zip_path, list = TRUE)   # lists the zip's contents (no extraction)
print(zip_contents)

csv_name <- zip_contents$Name[grepl("\\.csv$", zip_contents$Name, ignore.case = TRUE)]
stopifnot(length(csv_name) == 1)  #expect exactly one CSV inside

unzip(zip_path, files = csv_name, exdir = "data/raw")
csv_path <- file.path("data/raw", csv_name)
stopifnot(file.exists(csv_path))
cat("CSV found at:", csv_path, "\n")

#4. Record the data source
if (downloaded_now) {
  # tools::md5sum() makes a fingerprint of the file; any change alters it.
  raw_md5 <- unname(tools::md5sum(csv_path))
  
  metadata <- c(
    "Data source: Kenneth R. French Data Library",
    paste("Source page:", source_page),
    paste("File URL:", file_url),
    paste("Download time:", download_time),
    "Dataset: Fama/French 3 Research Factors, monthly",
    "Variable used: Mkt-RF (market excess return, in percentage points)",
    "Planned period: Jan 2015 to Dec 2024 (to be verified in the file)",
    paste("CSV file name:", csv_name),
    paste("Raw CSV MD5 checksum:", raw_md5)
  )
  writeLines(metadata, meta_path)
}
cat(readLines(meta_path), sep = "\n")

#5. Inspect the raw file
raw_lines <- readLines(csv_path)# each line of the file as a piece of text

length(raw_lines) # total number of lines
head(raw_lines, 8) # the top of the file
grep("Annual", raw_lines) # line number(s) mentioning "Annual"
tail(raw_lines, 5) # the bottom of the file
grep("^ *201501,|^ *202412,", raw_lines, value = TRUE)# our two boundary months

# =============================================================================
# 02_clean_data.R
# Turn the raw Fama/French file into a clean monthly market excess return series for Jan 2015 - Dec 2024, in decimals.
# =============================================================================

stopifnot(dir.exists("data/raw"), dir.exists("data/processed"))

#1. Locate and read the raw file
csv_files <- list.files("data/raw", pattern = "\\.csv$", ignore.case = TRUE,
                        full.names = TRUE)
stopifnot(length(csv_files) == 1)
raw_lines <- readLines(csv_files)

#2. Keep only monthly data rows
is_monthly    <- grepl("^\\s*[0-9]{6}\\s*,", raw_lines)
monthly_lines <- raw_lines[is_monthly]

length(monthly_lines) # number of monthly rows in the whole file
head(monthly_lines, 3) # first rows
tail(monthly_lines, 3) # last rows

#3. Parse into a data frame
ff <- read.csv(
  text        = paste(monthly_lines, collapse = "\n"),
  header      = FALSE,
  col.names   = c("yyyymm", "mkt_rf_pct", "smb_pct", "hml_pct", "rf_pct"),
  colClasses  = c("character", rep("numeric", 4)),
  strip.white = TRUE
)
str(ff)   #1 text column + 4 numeric columns

#4. Dates: parse and sort

ff$date <- as.Date(paste0(trimws(ff$yyyymm), "01"), format = "%Y%m%d")
ff      <- ff[order(ff$date), ]

#5. Quality checks on the whole file
anyNA(ff$date) # expect FALSE (all dates parsed)
anyDuplicated(ff$date)# expect 0 (no duplicate months)
colSums(is.na(ff))  # expect all zeros (no NA values)
sum(ff$mkt_rf_pct %in% c(-99.99, -999))  # expect 0 (no missing-value codes)

all_months <- seq(min(ff$date), max(ff$date), by = "month")
all_months[!(all_months %in% ff$date)]# expect: Date of length 0 (no gaps)
range(ff$date)# first and last month in the file

# 6. Select the fixed window: Jan 2015 - Dec 2024 
start_date <- as.Date("2015-01-01")
end_date   <- as.Date("2024-12-01")
mkt <- ff[ff$date >= start_date & ff$date <= end_date, c("date", "mkt_rf_pct")]

expected_months <- seq(start_date, end_date, by = "month")
nrow(mkt)  # expect 120
stopifnot(nrow(mkt) == 120, all(mkt$date == expected_months))

# 7. Convert percentage points to decimals 
mkt$mkt_excess <- mkt$mkt_rf_pct / 100
rownames(mkt)  <- NULL

# 8. Sanity checks on the cleaned series
summary(mkt$mkt_excess)
mean(mkt$mkt_excess)# average monthly market excess return (decimal)
sd(mkt$mkt_excess) # monthly standard deviation (decimal)
mkt[which.min(mkt$mkt_excess), ]   # worst month
mkt[which.max(mkt$mkt_excess), ]   # best month

# Start dates of the shorter windows (final 36 and 60 months ending Dec 2024)
tail(mkt, 36)$date[1]
tail(mkt, 60)$date[1]

# 9. Save the processed data
write.csv(mkt, "data/processed/mkt_excess_2015_2024.csv", row.names = FALSE)

# Read it back to confirm the saved file is what we expect
check <- read.csv("data/processed/mkt_excess_2015_2024.csv")
dim(check)                 # expect 120 rows, 3 columns
head(check, 3)

# =============================================================================
# 03_one_fund.R
# simulate ONE fund, estimate CAPM alpha by OLS, and run a one-sided 5% test of H0: alpha <= 0 vs H1: alpha > 0.
# =============================================================================

# 1. Load the cleaned market data
mkt <- read.csv("data/processed/mkt_excess_2015_2024.csv")
mkt$date <- as.Date(mkt$date)
stopifnot(nrow(mkt) == 120, !anyNA(mkt$mkt_excess))

#2. Choose the fund's TRUE parameters (monthly, decimals)
true_alpha <- 0.004     # 0.4% per month
true_beta  <- 1
resid_sd   <- 0.04      # 4% per month
T_months   <- 120
seed       <- 2026

#3. Select the market history
window <- tail(mkt, T_months)    # last T_months rows (ending Dec 2024)
market <- window$mkt_excess
range(window$date)               # expect 2015-01-01 to 2024-12-01

#4. Generate random residuals and the fund's excess returns
set.seed(seed)
eps <- rnorm(T_months, mean = 0, sd = resid_sd)# independent normal errors

fund_excess <- true_alpha + true_beta * market + eps

# Quick look: is the noise what we asked for?
c(mean_eps = mean(eps), sd_eps = sd(eps)) # sd should be near 0.04 (not exact)

# 5. Estimate the regression by OLS 
fit <- lm(fund_excess ~ market) # includes an intercept automatically
summary(fit)

#6. Pull out the numbers we need 
coef_tab  <- coef(summary(fit)) 
coef_tab

alpha_hat <- coef_tab["(Intercept)", "Estimate"]
alpha_se  <- coef_tab["(Intercept)", "Std. Error"]
t_alpha   <- coef_tab["(Intercept)", "t value"]
p_two     <- coef_tab["(Intercept)", "Pr(>|t|)"]
beta_hat  <- coef_tab["market", "Estimate"]
beta_se   <- coef_tab["market", "Std. Error"]
df        <- df.residual(fit) # should be T - 2 = 118

# 7. One-sided test of H0: alpha <= 0 vs H1: alpha > 0 
# pt() is the t distribution's cumulative probability. lower.tail = FALSE gives P(T > t), the UPPER-tail probability.
p_one <- pt(t_alpha, df = df, lower.tail = FALSE)
crit  <- qt(0.95, df = df)# critical value for a one-sided 5% test
detected <- p_one < 0.05

# Check against the rule: t > 0 -> p_two/2 ; t < 0 -> 1 - p_two/2
p_one_rule <- ifelse(t_alpha > 0, p_two / 2, 1 - p_two / 2)
stopifnot(isTRUE(all.equal(p_one, p_one_rule)))

#8. Check by hand (should match lm exactly)
beta_manual  <- cov(market, fund_excess) / var(market)
alpha_manual <- mean(fund_excess) - beta_manual * mean(market)
resid_manual <- fund_excess - alpha_manual - beta_manual * market
s2           <- sum(resid_manual^2) / (T_months - 2)   # residual variance estimate
Sxx          <- sum((market - mean(market))^2)
se_alpha_manual <- sqrt(s2 * (1 / T_months + mean(market)^2 / Sxx))

c(alpha_lm = alpha_hat, alpha_manual = alpha_manual)
c(beta_lm  = beta_hat,  beta_manual  = beta_manual)
c(se_lm    = alpha_se,  se_manual    = se_alpha_manual)

# What the standard error SHOULD be, using the TRUE residual SD:
theory_se <- resid_sd * sqrt(1 / T_months + mean(market)^2 / Sxx)
theory_se

# 9. Summary of this one fund
results_one <- data.frame(
  true_alpha = true_alpha, alpha_hat = alpha_hat, alpha_se = alpha_se,
  t_alpha = t_alpha, crit_5pct = crit, p_one_sided = p_one,
  detected = detected, beta_hat = beta_hat, df = df
)
print(t(results_one))# transposed so it reads down the page

# Arithmetic annualisation (12 x monthly alpha)
c(true_alpha_annual_arith = 12 * true_alpha, alpha_hat_annual_arith = 12 * alpha_hat)