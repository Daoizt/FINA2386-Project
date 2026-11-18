# Prepared Spotify study data

Run Rscript "SNA R/prepare_spotify.R" from the project root to reproduce these files.

Primary sample includes 2018-2020 releases with popularity from 0 to 100.
Catalogue variants match on normalized title, artist ID set, duration and four exact audio features. Earliest eligible release wins; track ID breaks ties.
This matching rule approximates recording identity using available metadata. See catalogue_duplicates.csv.
Superstar threshold is the type-7 90th follower percentile, 759915.4000 followers. Status is TRUE at or above this threshold. Missing follower counts remain unknown.
The threshold uses all credited artists, including solo artists, with valid followers in the primary sample. Keep it fixed in the popularity >=65 sensitivity sample.
Reference genre tags are exact matches for pop, dance pop, electropop, hip hop, rap, pop rap or trap.
H3 requires three retained tracks with all four complete audio features. Artist audio means use those complete tracks. Standardization uses all H3-eligible artists with equal artist weight.
The reference center gives each qualifying tagged artist equal weight. Reference members use leave-one-artist-out centers for their distance.
reference_distance is Euclidean distance in standardized audio space; audio_conformity is its negative. h3_superstars.csv is the target H3 study sample.
Followers and popularity reflect the supplied snapshot. Genre and follower metadata may be missing. Track counts refer to this source's eligible catalogue.
Hypothesis tests and network graphs are subsequent steps. Earlier outputs in SNA Results use a different sample.
