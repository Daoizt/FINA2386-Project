# FINA2386 | Speaker 3: Community Detection (2018-2020)
# ---- 1. Settings and packages -----------------------------------------------
DATA_DIR <- path.expand("~/Desktop/HKU/FINA2386")
OUT_DIR  <- file.path(DATA_DIR, "speaker3_R_outputs")
SEED <- 2386
RESOLUTION <- 1
TOP_SIZE <- 15
TOP_MAP <- 12
TOP_COLOURS <- 8
TOP_REACH <- 15

pkgs <- c("readr", "dplyr", "stringr", "igraph", "ggplot2", "scales")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
invisible(lapply(pkgs, library, character.only = TRUE))

BG <- "#F5F8FC"; TEXT <- "#19314A"; MUTED <- "#526980"
EDGE <- "#647894"; GRID <- "#D7E1EC"; OTHER <- "#CBD5E1"
PAL <- c("#1D7792", "#E59A58", "#4C9F70", "#D96C62", "#9270B5", "#9A6B5D",
         "#D76BB5", "#78838D", "#B9A14C", "#5A80C5", "#55A6A0", "#C87847")
names(PAL) <- paste0("C", 1:12)

# ---- 2. Read data and build the giant-component network -----------------
files <- file.path(DATA_DIR, c("tracks_clean.csv", "artists_clean.csv"))
if (!all(file.exists(files))) stop("Put tracks_clean.csv and artists_clean.csv in ~/Desktop/HKU/FINA2386")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

tracks <- read_csv(files[1], show_col_types = FALSE,
                   col_types = cols(id_artists = col_character(), .default = col_guess()))
artists <- read_csv(files[2], show_col_types = FALSE,
                    col_types = cols(id = col_character(), name = col_character(),
                                     genres = col_character(), .default = col_guess()))
stopifnot(all(c("id_artists", "year") %in% names(tracks)), all(c("id", "name") %in% names(artists)))
tracks <- tracks %>% filter(!is.na(year), year >= 2018, year <= 2020)
ids <- str_extract_all(ifelse(is.na(tracks$id_artists), "", tracks$id_artists), "[A-Za-z0-9]{22}")
if (any(lengths(ids) == 0)) stop("Some 2018-2020 tracks have no readable Spotify artist IDs.")

pairs <- bind_rows(lapply(ids, function(x) {
  x <- sort(unique(x))
  if (length(x) < 2) return(NULL)
  as.data.frame(t(combn(x, 2)), stringsAsFactors = FALSE)
}))
names(pairs) <- c("from", "to")
edges <- pairs %>% count(from, to, name = "weight")
g_all <- graph_from_data_frame(edges, directed = FALSE)
comp <- components(g_all)
g <- induced_subgraph(g_all, which(comp$membership == which.max(comp$csize)))

cat("Tracks:", nrow(tracks), " | Nodes:", vcount(g), " | Edges:", ecount(g), "\n")
if (vcount(g) != 6368 || ecount(g) != 21573)
  warning("Network size differs from Speaker 2 (expected 6,368 nodes / 21,573 edges). Check input files.")

# ---- 3. Weighted Louvain and community labels -------------------------------
set.seed(SEED)
louvain <- cluster_louvain(g, weights = E(g)$weight, resolution = RESOLUTION)
m <- membership(louvain); names(m) <- V(g)$name
groups <- split(names(m), m)
ord <- order(-lengths(groups), vapply(groups, min, character(1)))
ranked <- setNames(seq_along(ord), names(groups)[ord])
community_id <- as.integer(ranked[as.character(m)]); names(community_id) <- names(m)
Q <- modularity(g, membership = community_id[V(g)$name],
                weights = E(g)$weight, resolution = RESOLUTION)

artist_lookup <- artists %>% select(id, name, any_of("genres")) %>% distinct(id, .keep_all = TRUE)
nodes <- tibble(artist_id = V(g)$name) %>%
  left_join(artist_lookup, by = c("artist_id" = "id")) %>%
  mutate(artist = ifelse(is.na(name) | name == "", artist_id, name),
         community_id = unname(community_id[artist_id]),
         community = paste0("C", community_id))

sizes <- nodes %>% count(community_id, community, name = "n_artists") %>%
  arrange(community_id) %>% mutate(share_percent = 100 * n_artists / vcount(g))

# ---- 4. Artist and community connection measures ----------------------------
e <- as_data_frame(g, what = "edges") %>%
  transmute(from = as.character(from), to = as.character(to), weight = as.numeric(weight)) %>%
  left_join(nodes %>% select(artist_id, c_from = community, id_from = community_id),
            by = c("from" = "artist_id")) %>%
  left_join(nodes %>% select(artist_id, c_to = community, id_to = community_id),
            by = c("to" = "artist_id"))

inside <- e %>% filter(id_from == id_to)
within <- bind_rows(transmute(inside, artist_id = from, w = weight),
                    transmute(inside, artist_id = to, w = weight)) %>%
  group_by(artist_id) %>% summarise(within_degree = n(), within_strength = sum(w), .groups = "drop")
outside <- e %>% filter(id_from != id_to)
cross <- bind_rows(transmute(outside, artist_id = from, external = c_to),
                    transmute(outside, artist_id = to, external = c_from)) %>%
  group_by(artist_id) %>% summarise(external_communities = n_distinct(external),
                                    cross_collaborators = n(), .groups = "drop")

membership_df <- nodes %>%
  left_join(within, by = "artist_id") %>% left_join(cross, by = "artist_id") %>%
  mutate(across(c(within_degree, within_strength, external_communities, cross_collaborators),
                ~dplyr::coalesce(.x, 0))) %>%
  mutate(degree = degree(g)[match(artist_id, V(g)$name)],
         weighted_strength = strength(g, weights = E(g)$weight)[match(artist_id, V(g)$name)]) %>%
  arrange(community_id, desc(within_strength), desc(within_degree))

inter <- outside %>% mutate(a = pmin(id_from, id_to), b = pmax(id_from, id_to)) %>%
  group_by(a, b) %>% summarise(artist_pair_edges = n(), shared_track_weight = sum(weight), .groups = "drop") %>%
  mutate(community_1 = paste0("C", a), community_2 = paste0("C", b)) %>%
  select(community_1, community_2, artist_pair_edges, shared_track_weight) %>%
  arrange(desc(shared_track_weight), desc(artist_pair_edges))

reach <- membership_df %>% filter(external_communities > 0) %>%
  arrange(desc(external_communities), desc(cross_collaborators), desc(weighted_strength), artist_id) %>%
  mutate(rank = row_number()) %>%
  select(rank, artist, artist_id, community, external_communities,
         cross_collaborators, degree, weighted_strength)

representatives <- membership_df %>% group_by(community_id, community) %>%
  slice_max(within_strength, n = 5, with_ties = FALSE) %>% ungroup() %>%
  select(community, artist, artist_id, within_degree, within_strength, degree, weighted_strength)
rosters <- membership_df %>%
  select(community, community_id, artist, artist_id, within_degree, within_strength)

# ---- 6. Figure 1: full network coloured by community ------------------------
set.seed(SEED)
xy <- layout_with_drl(g, weights = NA)
plot_nodes <- nodes %>% mutate(x = xy[, 1], y = xy[, 2],
                               degree = degree(g)[match(artist_id, V(g)$name)],
                               colour_group = ifelse(community_id <= TOP_COLOURS, community, "Other communities"))
plot_edges <- e %>% select(from, to) %>%
  left_join(plot_nodes %>% select(artist_id, x, y), by = c("from" = "artist_id")) %>%
  left_join(plot_nodes %>% select(artist_id, xend = x, yend = y), by = c("to" = "artist_id"))
cols1 <- c(PAL[1:TOP_COLOURS], "Other communities" = OTHER)
p1 <- ggplot() +
  geom_segment(data = plot_edges, aes(x, y, xend = xend, yend = yend),
               colour = EDGE, alpha = .075, linewidth = .18) +
  geom_point(data = plot_nodes, aes(x, y, colour = colour_group, size = degree), alpha = .92) +
  scale_colour_manual(values = cols1, name = "Community") +
  scale_size_continuous(range = c(.35, 2.2), guide = "none") + coord_equal() + theme_void() +
  labs(title = "Artist Collaboration Network by Louvain Community",
       subtitle = paste(vcount(g), "artists |", ecount(g), "ties |", nrow(sizes), "communities"),
       caption = paste("Eight largest communities are coloured; remaining", nrow(sizes) - TOP_COLOURS, "are grey.")) +
  theme(plot.background = element_rect(fill = BG, colour = NA),
        panel.background = element_rect(fill = BG, colour = NA),
        plot.title = element_text(face = "bold", size = 18, colour = TEXT),
        plot.subtitle = element_text(colour = MUTED), plot.caption = element_text(colour = MUTED),
        legend.text = element_text(colour = MUTED), legend.title = element_text(colour = TEXT))
ggsave(file.path(OUT_DIR, "01_Community_Network_Louvain_R.png"), p1, width = 15, height = 10.5, dpi = 300, bg = BG)
write_csv(plot_nodes %>% select(artist_id, artist, community, x, y),
          file.path(OUT_DIR, "speaker3_layout_coordinates_R.csv"))

# ---- 7. Figure 2: sizes of the 15 largest communities -----------------------
top_sizes <- sizes %>% slice_head(n = TOP_SIZE) %>% arrange(n_artists) %>%
  mutate(community = factor(community, levels = community))
p2 <- ggplot(top_sizes, aes(community, n_artists)) +
  geom_col(fill = PAL[1], width = .68) +
  geom_text(aes(label = paste0(comma(n_artists), " (", sprintf("%.1f", share_percent), "%)")),
            hjust = -.12, size = 3.2, colour = TEXT) + coord_flip(clip = "off") +
  scale_y_continuous(labels = comma, expand = expansion(mult = c(0, .3))) +
  labs(title = "Largest 15 Louvain Communities", x = "Community (ranked by size)", y = "Artists") +
  theme_minimal(base_size = 12) +
  theme(plot.background = element_rect(fill = BG, colour = NA),
        panel.background = element_rect(fill = BG, colour = NA),
        plot.title = element_text(face = "bold", size = 18, colour = TEXT),
        axis.text = element_text(colour = MUTED), axis.title = element_text(colour = TEXT),
        panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
        panel.grid.major.x = element_line(colour = GRID))
ggsave(file.path(OUT_DIR, "02_Community_Size_Top15_R.png"), p2, width = 10.5, height = 7.2, dpi = 300, bg = BG)

# ---- 8. Figure 3: connections among the 12 largest communities --------------
top_names <- head(sizes$community, TOP_MAP)
inter12 <- inter %>% filter(community_1 %in% top_names, community_2 %in% top_names)
vertices <- sizes %>% slice_head(n = TOP_MAP) %>% transmute(name = community, community, community_id, n_artists)
meta_edges <- inter12 %>% transmute(from = community_1, to = community_2,
                                    shared_track_weight, artist_pair_edges)
meta <- graph_from_data_frame(meta_edges, directed = FALSE, vertices = vertices)
set.seed(SEED)
meta_xy <- if (ecount(meta)) layout_with_fr(meta, weights = E(meta)$shared_track_weight) else layout_in_circle(meta)
meta_nodes <- vertices %>% mutate(x = meta_xy[, 1], y = meta_xy[, 2])
meta_lines <- as_data_frame(meta, what = "edges") %>%
  left_join(meta_nodes %>% select(name, x, y), by = c("from" = "name")) %>%
  left_join(meta_nodes %>% select(name, xend = x, yend = y), by = c("to" = "name"))
p3 <- ggplot() +
  geom_segment(data = meta_lines, aes(x, y, xend = xend, yend = yend, linewidth = shared_track_weight),
               colour = EDGE, alpha = .58, lineend = "round") +
  scale_linewidth(range = c(.6, 5.5), guide = "none") +
  geom_point(data = meta_nodes, aes(x, y, size = n_artists, fill = community),
             shape = 21, colour = "white", stroke = 1.2) +
  scale_size_continuous(range = c(8, 18), guide = "none") +
  scale_fill_manual(values = PAL, guide = "none") +
  geom_text(data = meta_nodes, aes(x, y, label = paste0(community, "\n", comma(n_artists))),
            colour = "white", fontface = "bold", size = 3.1) + coord_equal() + theme_void() +
  labs(title = paste("Connections Between the", TOP_MAP, "Largest Communities"),
       subtitle = "Node size = artists | Edge width = shared-track weight") +
  theme(plot.background = element_rect(fill = BG, colour = NA),
        panel.background = element_rect(fill = BG, colour = NA),
        plot.title = element_text(face = "bold", size = 18, colour = TEXT),
        plot.subtitle = element_text(colour = MUTED))
ggsave(file.path(OUT_DIR, "03_Intercommunity_Network_Top12_R.png"), p3, width = 11, height = 8, dpi = 300, bg = BG)
write_csv(inter12, file.path(OUT_DIR, "speaker3_intercommunity_top12_R.csv"))

# ---- 9. Figure 4: top artists, coloured by their own community --------------
top_reach <- reach %>% slice_head(n = TOP_REACH) %>%
  arrange(external_communities, cross_collaborators) %>%
  mutate(label = paste0(artist, " (", community, ")"),
         colour_group = ifelse(as.integer(sub("C", "", community)) <= TOP_MAP, community, "Other communities"),
         label = factor(make.unique(label), levels = make.unique(label)))
cols4 <- c(PAL, "Other communities" = OTHER)
p4 <- ggplot(top_reach, aes(label, external_communities, fill = colour_group)) +
  geom_col(width = .68) +
  geom_text(aes(label = paste(external_communities, "communities |", cross_collaborators, "collaborators")),
            hjust = -.08, size = 3, colour = TEXT) + coord_flip(clip = "off") +
  scale_fill_manual(values = cols4, name = "Artist's own community") +
  scale_y_continuous(breaks = pretty_breaks(), expand = expansion(mult = c(0, .52))) +
  labs(title = "Artists with the Broadest Cross-Community Reach", x = NULL,
       y = "Different external communities represented among direct collaborators") +
  theme_minimal(base_size = 12) +
  theme(plot.background = element_rect(fill = BG, colour = NA),
        panel.background = element_rect(fill = BG, colour = NA),
        plot.title = element_text(face = "bold", size = 17, colour = TEXT),
        axis.text = element_text(colour = MUTED), axis.title = element_text(colour = TEXT),
        panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
        panel.grid.major.x = element_line(colour = GRID),
        legend.title = element_text(colour = TEXT), legend.text = element_text(colour = MUTED))
ggsave(file.path(OUT_DIR, "04_CrossCommunity_Reach_Top15_CommunityColors_R.png"),
       p4, width = 11.5, height = 7.5, dpi = 300, bg = BG)
write_csv(top_reach, file.path(OUT_DIR, "speaker3_top15_cross_community_reach_R.csv"))