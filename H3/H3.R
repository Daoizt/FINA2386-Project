# Auto-install any missing packages before loading
required_pkgs <- c("tidyverse", "igraph", "sandwich", "lmtest", "ggrepel")
missing_pkgs <- setdiff(required_pkgs, rownames(installed.packages()))
if (length(missing_pkgs) > 0) {
  options(install.packages.compile.from.source = "never")
  install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
}

library(tidyverse)
library(igraph)
library(sandwich)
library(lmtest)
library(ggrepel)

# Load and prepare data
sup <- read_csv("h3_superstars.csv", show_col_types = FALSE) %>%
  mutate(
    log_track_count = log(track_count),
    followers_per_track = followers / audio_track_count,
    log_followers_per_track = log(followers_per_track)
  )

# Primary and exploratory OLS regressions (HC3 robust SEs)
m_primary <- lm(average_popularity ~ audio_conformity + log_track_count + mean_release_year, data = sup)
coeftest(m_primary, vcov = vcovHC(m_primary, type = "HC3"))

m_exploratory <- lm(log_followers_per_track ~ audio_conformity + log_track_count + mean_release_year, data = sup)
coeftest(m_exploratory, vcov = vcovHC(m_exploratory, type = "HC3"))

# Robustness check 1: Minimum track count thresholds (>=3, >=5, >=10)
run_threshold_check <- function(min_tracks) {
  df_sub <- sup %>% filter(audio_track_count >= min_tracks)
  mod <- lm(average_popularity ~ audio_conformity + log_track_count + mean_release_year, data = df_sub)
  res <- coeftest(mod, vcov = vcovHC(mod, type = "HC3"))
  tibble(
    min_tracks = min_tracks,
    n = nrow(df_sub),
    beta_conformity = res["audio_conformity", "Estimate"],
    se_hc3 = res["audio_conformity", "Std. Error"],
    p_value = res["audio_conformity", "Pr(>|t|)"]
  )
}

robust_tracks <- bind_rows(
  run_threshold_check(3),
  run_threshold_check(5),
  run_threshold_check(10)
)

# Robustness check 2: Non-Reference Artists Only (excluding reference group)
sup_non_ref <- sup %>% filter(!as.logical(reference_member))
m_non_ref <- lm(average_popularity ~ audio_conformity + log_track_count + mean_release_year, data = sup_non_ref)
res_non_ref <- coeftest(m_non_ref, vcov = vcovHC(m_non_ref, type = "HC3"))
robust_non_ref <- tibble(
  model = "Non-Reference Artists Only",
  n = nrow(sup_non_ref),
  beta_conformity = res_non_ref["audio_conformity", "Estimate"],
  se_hc3 = res_non_ref["audio_conformity", "Std. Error"],
  p_value = res_non_ref["audio_conformity", "Pr(>|t|)"]
)

# Audio-similarity k-NN network & robustness check 3 (k = 5, 10, 15)
audio_mat <- sup %>%
  select(danceability, energy, valence, acousticness) %>%
  scale() %>%
  as.matrix()

dist_mat <- as.matrix(dist(audio_mat, method = "euclidean"))

build_knn_network <- function(dist_matrix, k = 10) {
  n <- nrow(dist_matrix)
  adj <- matrix(0, nrow = n, ncol = n)
  for (i in 1:n) {
    neighbors <- order(dist_matrix[i, ])[2:(k + 1)]
    adj[i, neighbors] <- 1
    adj[neighbors, i] <- 1
  }
  graph_from_adjacency_matrix(adj, mode = "undirected", diag = FALSE)
}

robust_knn <- map_dfr(c(5, 10, 15), function(k_val) {
  g <- build_knn_network(dist_mat, k = k_val)
  df_tmp <- sup %>%
    mutate(
      deg_cent = degree(g, normalized = TRUE),
      eig_cent = eigen_centrality(g)$vector
    )
  mod <- lm(average_popularity ~ eig_cent + log_track_count + mean_release_year, data = df_tmp)
  res <- coeftest(mod, vcov = vcovHC(mod, type = "HC3"))
  tibble(
    k = k_val,
    beta_eig_cent = res["eig_cent", "Estimate"],
    se_hc3 = res["eig_cent", "Std. Error"],
    p_value = res["eig_cent", "Pr(>|t|)"]
  )
})

# Combine & Export Slide 26 Robustness Summary Table
robustness_table <- bind_rows(
  robust_tracks %>%
    mutate(
      Model_Specification = c("Baseline Primary Model", "Stricter Track Threshold", "High-Output Superstars"),
      Sample_Parameter = sprintf(">= %d tracks (N = %s)", min_tracks, format(n, big.mark = ",")),
      Beta = round(beta_conformity, 3),
      HC3_SE = round(se_hc3, 3),
      p_value = round(p_value, 3)
    ) %>%
    select(Model_Specification, Sample_Parameter, Beta, HC3_SE, p_value),
  robust_non_ref %>%
    mutate(
      Model_Specification = "Non-Reference Artists Only",
      Sample_Parameter = sprintf("Excl. ref. group (N = %s)", format(n, big.mark = ",")),
      Beta = round(beta_conformity, 3),
      HC3_SE = round(se_hc3, 3),
      p_value = round(p_value, 3)
    ) %>%
    select(Model_Specification, Sample_Parameter, Beta, HC3_SE, p_value),
  robust_knn %>%
    filter(k %in% c(10, 15)) %>%
    mutate(
      Model_Specification = "k-NN Network Centrality",
      Sample_Parameter = sprintf("k = %d neighbors (N = %s)", k, format(nrow(sup), big.mark = ",")),
      Beta = round(beta_eig_cent, 3),
      HC3_SE = round(se_hc3, 3),
      p_value = round(p_value, 3)
    ) %>%
    select(Model_Specification, Sample_Parameter, Beta, HC3_SE, p_value)
)

print(robustness_table)
write_csv(robustness_table, "table_h3_robustness.csv")

# Figure 1: Adjusted Conformity-Popularity Plot
pred_grid <- tibble(
  audio_conformity = seq(min(sup$audio_conformity), max(sup$audio_conformity), length.out = 200),
  log_track_count = mean(sup$log_track_count),
  mean_release_year = mean(sup$mean_release_year)
)
preds <- predict(m_primary, newdata = pred_grid, interval = "confidence")
pred_grid <- bind_cols(pred_grid, as_tibble(preds))

highlight_names <- c("Taylor Swift", "Billie Eilish", "The Weeknd", "Drake", "BTS", "Bad Bunny", "Lana Del Rey", "Ariana Grande")
sup_labels <- sup %>% filter(name %in% highlight_names)

p1 <- ggplot() +
  geom_point(data = sup, aes(x = audio_conformity, y = average_popularity, size = followers / 1e6),
             alpha = 0.35, color = "#5B6ABF") +
  geom_ribbon(data = pred_grid, aes(x = audio_conformity, ymin = lwr, ymax = upr),
              fill = "#E07A5F", alpha = 0.2) +
  geom_line(data = pred_grid, aes(x = audio_conformity, y = fit),
            color = "#D95F02", linewidth = 1.1) +
  geom_text_repel(data = sup_labels, aes(x = audio_conformity, y = average_popularity, label = name),
                  size = 3.2, fontface = "bold", max.overlaps = 15, box.padding = 0.4) +
  scale_size_continuous(name = "Followers (M)", range = c(1.5, 6)) +
  labs(
    title = "H3: Audio Conformity vs. Average Track Popularity (N = 1,005 Superstars)",
    subtitle = "Adjusted OLS fit holding log(track count) and mean release year at sample means (95% CI shaded)",
    x = "Audio Conformity (-Euclidean Distance to Pop/Hip-Hop Reference)",
    y = "Average Track Popularity"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold"),
    legend.position = "right"
  )

ggsave("fig_h3_conformity_popularity.png", p1, width = 9, height = 6, dpi = 300)

# Figure 2: Audio-Similarity Network (Top 120 Superstars, k = 5)
top120_idx <- order(sup$followers, decreasing = TRUE)[1:120]
sub_sup <- sup[top120_idx, ]
sub_dist <- dist_mat[top120_idx, top120_idx]
g_sub <- build_knn_network(sub_dist, k = 5)

V(g_sub)$name <- sub_sup$name
V(g_sub)$conformity <- sub_sup$audio_conformity
V(g_sub)$followers <- sub_sup$followers

pal <- colorRampPalette(c("#3B528B", "#21908C", "#FDE725", "#D95F02"))(100)
conf_scaled <- as.numeric(cut(V(g_sub)$conformity, breaks = 100))
V(g_sub)$color <- pal[conf_scaled]

label_vec <- ifelse(V(g_sub)$name %in% highlight_names, V(g_sub)$name, NA)

png("fig_h3_audio_network.png", width = 2400, height = 2000, res = 300)
set.seed(2026)
lay <- layout_with_fr(g_sub)
plot(
  g_sub,
  layout = lay,
  vertex.size = 3 + 4 * (V(g_sub)$followers / max(V(g_sub)$followers)),
  vertex.color = V(g_sub)$color,
  vertex.frame.color = "white",
  vertex.label = label_vec,
  vertex.label.cex = 0.75,
  vertex.label.color = "black",
  vertex.label.font = 2,
  edge.color = adjustcolor("grey60", alpha.f = 0.35),
  edge.width = 0.7,
  main = "H3: Audio-Similarity k-NN Network (Top 120 Superstars, k = 5)"
)
legend(
  "bottomleft",
  legend = c("High Conformity (Mainstream Core)", "Medium", "Low Conformity (Distinctive Periphery)"),
  pt.bg = c("#D95F02", "#21908C", "#3B528B"),
  pch = 21, pt.cex = 1.5, bty = "n", cex = 0.85
)
dev.off()