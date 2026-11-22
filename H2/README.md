# H2 Structural Brokerage and Spotify Popularity

H2 tests whether artists who bridge collaboration groups have more followers but lower average track popularity.

**The results depend on the sample.** Brokerage is positively associated with both outcomes across the full catalogue. The predicted popularity trade-off appears in the subset of already-popular recordings.

## Files

- [H2.Rmd](H2.Rmd) contains the methods, all R analysis functions, models, figures and interpretation.
- [output/H2.pdf](output/H2.pdf) is the rendered report.
- [../Prepared Data](<../Prepared Data>) contains the shared cleaned input data.

The R Markdown file reruns the analysis and creates its tables and figures during rendering.

## Render the PDF

Download or clone the repository, including both H2 and Prepared Data. From the repository root, open an R console and install the required packages once.

~~~r
install.packages(c("rmarkdown", "knitr", "data.table", "igraph", "sandwich"))
~~~

Rendering also requires Pandoc, Tectonic on PATH, and the Arial font specified in the document. RStudio supplies Pandoc. Tectonic downloads its TeX resources on first use, so allow an internet connection for the initial compilation.

Run this from the repository root.

~~~r
rmarkdown::render(
  "H2/H2.Rmd",
  output_format = "pdf_document",
  output_dir = "H2/output"
)
~~~

This writes the report to H2/output/H2.pdf. Generated CSV tables, model data, fitted models, figures and session information are also written to H2/output.

The default data lookup is ../Prepared Data relative to H2.Rmd. The data_dir and output_dir parameters can override the input and analysis-output folders. Relative parameter paths are resolved from the H2 document folder.

## Samples and network construction

Both samples use cleaned 2018-2020 recordings with Spotify artist IDs and catalogue deduplication already applied.

| Sample | Recordings | Credited artists | Largest-component artists | Regression artists |
|---|---:|---:|---:|---:|
| Full popularity range | 35,805 | 18,401 | 6,368 | 5,642 |
| Popularity >=65 | 5,323 | 3,390 | 1,381 | 1,348 |

The popularity threshold is applied after deduplication. Each run rebuilds the artist-track bipartite network and its weighted artist projection. Edge weights count shared retained recordings. The analysis uses the largest connected component separately within each sample.

Artist averages and track counts include retained solo recordings. Both outcome models use the same complete-case artists with positive observed followers.

## Measures and models

Brokerage is the reciprocal of weighted Burt constraint. Weighted eigenvector centrality, track count and mean danceability are controls.

~~~r
log(followers) ~ structural_holes + eigenvector + song_count + avg_danceability

avg_popularity ~ structural_holes + eigenvector + song_count + avg_danceability
~~~

Here structural_holes equals 1 / constraint. These are the original H2 model specifications applied to the cleaned data.

Inference uses two-sided t tests with HC1 robust standard errors and nominal 95% confidence intervals. Holm correction covers the two H2 outcomes within each sample separately. The analysis checks HC1 covariance against its direct matrix calculation.

## Results

| Sample | Outcome | Brokerage coefficient | 95% HC1 interval |
|---|---|---:|---|
| Full popularity range | Log followers | +0.256 | [0.216, 0.296] |
| Full popularity range | Mean popularity | +1.383 | [1.243, 1.522] |
| Popularity >=65 | Log followers | +0.160 | [0.111, 0.210] |
| Popularity >=65 | Mean popularity | -0.224 | [-0.302, -0.146] |

All four raw p-values are below .001 and remain below .001 after the within-H2 corrections.

These results support a popularity trade-off within the high-popularity subset. The full sample does not support a general popularity penalty. Filtering changes the graph, artist cohort and outcomes being averaged.

Structural brokerage does not directly establish genre crossover. Followers and popularity are snapshot measures. HC1 addresses heteroskedasticity but does not fully account for dependence among collaborators. The results describe conditional associations.

## Figures

The report includes three R-generated exhibits.

1. H2_F1 pairs an artist-track graph with its matching five-artist projection to explain brokerage.
2. H2_F2 compares brokerage coefficients and 95% HC1 intervals across samples and outcomes.
3. H2_F3 shows adjusted predictions, holding controls at their sample means.

The small network is an illustrative example. Model estimates use the complete eligible regression samples.

## Merge with H1 and H3

Rendering creates the following integration assets in output.

| Generated file | Use |
|---|---|
| h2_manuscript_insert.md | Methods, results and limitations for the group report |
| h2_regression_table.md | Complete four-model regression table |
| h2_coefficients.csv | Every coefficient and its uncertainty |
| h2_estimates.csv | Focal brokerage estimates and within-H2 adjusted p-values |
| H2_F1-H2_F3 PDF and PNG figures | Manuscript and presentation figures |
| h2_input_checksums.csv | Input file verification |
| h2_session_info.txt | R environment record |

The estimate tables use hypothesis, sample, primary, outcome and term identifiers. Use the unadjusted p_value column when combining the agreed primary tests across H1-H3. The p_holm_h2 column only adjusts H2 outcomes within each sample.

Copy the narrative into the group report, shorten it to fit the shared word limit, and renumber the figure references when combining hypotheses.

