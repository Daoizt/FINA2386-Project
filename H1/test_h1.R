# From the project root: Rscript H1/test_h1.R
set.seed(2386)
read_data <- function(file) read.csv(file.path("Prepared Data", file))
tracks <- read_data("tracks_clean.csv")
artists <- read_data("artists_clean.csv")
credits <- read_data("artist_track_credits.csv")
groups <- split(match(credits$artist_id, artists$id), credits$track_id)
groups <- groups[tracks$id]
stopifnot(!anyNA(unlist(groups)), all(lengths(groups) == tracks$artist_count))
B <- 4999
network_tables <- list()
model_tables <- list()

analyze <- function(label, status, selected) {
  g <- groups[selected & lengths(groups) >= 2]
  t <- tracks[match(names(g), tracks$id), ]
  # Unknown endpoints contribute no status pairs. Known endpoints of the
  # same recording still form observed ties.
  pairs <- lapply(g, function(ids) {
    ids <- sort(ids[!is.na(status[ids])])
    if (length(ids) >= 2) t(combn(ids, 2))
  })
  e <- do.call(rbind, pairs)
  unique_edges <- unique(e)
  degree <- tabulate(as.vector(unique_edges), nrow(artists))
  bins <- cut(degree, c(0,1,2,4,8,16,32,64,Inf))
  strata <- split(which(degree > 0), bins[degree > 0], drop = TRUE)
  # One pair occurrence per shared recording implements edge weights.
  measure <- function(s) {
    left <- s[e[,1]]
    right <- s[e[,2]]
    endpoint <- mean(c(left, right))
    joint <- mean(left & right)
    c(r = (joint - endpoint^2)/(endpoint*(1-endpoint)), share = joint/endpoint)
  }
  observed <- measure(status)
  draws <- replicate(B, {
    shuffled <- status
    for (ix in strata) shuffled[ix] <- status[ix[sample.int(length(ix))]]
    measure(shuffled)
  })
  net <- data.frame(sample=label, artists=sum(degree>0), edges=nrow(unique_edges),
                    pair_credits=nrow(e), r=observed[1], share=observed[2],
                    null_r=mean(draws[1,]), null_share=mean(draws[2,]),
                    null_low=unname(quantile(draws[1,],.025)), null_high=unname(quantile(draws[1,],.975)),
                    p=(1+sum(draws[1,]>=observed[1]))/(B+1))
  if (label=="primary") {
    pdf("H1/assortativity.pdf",width=7,height=4)
    hist(draws[1,], breaks=35, xlim=range(draws[1,], observed[1]), col="grey80",
         main="Status mixing after shuffling within degree groups",xlab="Weighted status assortativity")
    abline(v=observed[1],col="firebrick",lwd=3)
    legend("topright",paste("Observed", round(observed[1],3)),text.col="firebrick",bty="n")
    dev.off()
  }
  nstar <- vapply(g, function(ix) sum(status[ix]), numeric(1))
  use <- !is.na(nstar) & nstar>0
  t <- t[use,]
  g <- g[use]
  t$all_star <- as.integer(nstar[use]==lengths(g))
  # Continuous credit count avoids singleton fixed effects for large ensembles.
  f <- popularity ~ all_star + factor(year)
  if (length(unique(t$artist_count))>1) f <- update(f, . ~ . + artist_count)
  model <- lm(f,t)
  X <- model.matrix(model)
  influence <- drop(X %*% solve(crossprod(X))[, "all_star"]) * residuals(model)
  hc3 <- sqrt(sum((influence/(1-hatvalues(model)))^2))
  # Add covariance once for each distinct pair of recordings sharing ANY
  # artist. Assumes disjoint-credit recordings have independent scores.
  by_artist <- split(rep(seq_along(g), lengths(g)), unlist(g))
  covariance <- 0
  for (j in seq_along(g)) {
    neighbors <- unique(unlist(by_artist[as.character(g[[j]])], use.names=FALSE))
    covariance <- covariance + influence[j]*sum(influence[neighbors[neighbors>j]])
  }
  se <- sqrt(sum(influence^2)+2*covariance)
  b <- unname(coef(model)["all_star"])
  reg <- data.frame(sample=label, all_star=sum(t$all_star), mixed=sum(1-t$all_star),
                    difference=b, shared_artist_se=se, low=b-1.96*se, high=b+1.96*se,
                    p=2*pnorm(-abs(b/se)), hc3_se=hc3)
  list(network=net, regression=reg)
}
specs <- list(primary=list(artists$superstar, rep(TRUE,nrow(tracks))),
              duets=list(artists$superstar, tracks$artist_count==2),
              popularity65=list(artists$superstar, tracks$popularity>=65),
              five_million=list(artists$followers>=5e6, rep(TRUE,nrow(tracks))),
              popularity65_five_million=list(artists$followers>=5e6, tracks$popularity>=65))
for (label in names(specs)) {
  result <- analyze(label, specs[[label]][[1]], specs[[label]][[2]])
  network_tables[[label]] <- result$network
  model_tables[[label]] <- result$regression
}
net <- do.call(rbind,network_tables)
reg <- do.call(rbind,model_tables)
# H1-only adjustment. Retain raw p for the group's final cross-H1/H2/H3 family.
adjusted <- p.adjust(c(net$p[1],reg$p[1]),"holm")
net$holm_H1 <- c(adjusted[1],rep(NA,nrow(net)-1))
reg$holm_H1 <- c(adjusted[2],rep(NA,nrow(reg)-1))
write.csv(net,"H1/network_results.csv",row.names=FALSE)
write.csv(reg,"H1/popularity_results.csv",row.names=FALSE)
pdf("H1/popularity.pdf",width=8,height=4)
par(mar=c(4,11,2,1))
labels <- c("Primary","Duets only","Popularity 65+","5M threshold","65+ and 5M")
y <- rev(seq_len(nrow(reg)))
plot(reg$difference,y,yaxt="n",ylab="",xlim=range(0,reg$low,reg$high),pch=19,
     xlab="Adjusted Spotify popularity difference (all-superstar minus mixed)")
axis(2,at=y,labels=labels,las=1)
segments(reg$low,y,reg$high,y)
abline(v=0,lty=2)
dev.off()

# Select a recognizable ego by a reproducible rule: highest-followed artist
# with eligible duets of both types. Show the most popular duet of each type.
duets <- groups[lengths(groups)==2]
for (ego in order(artists$followers,decreasing=TRUE,na.last=NA)) {
  my <- duets[vapply(duets,function(ix) ego %in% ix,logical(1))]
  partners <- vapply(my,function(ix) ix[ix!=ego],integer(1))
  kinds <- artists$superstar[partners]
  if (any(kinds %in% TRUE) && any(kinds %in% FALSE)) break
}
popular <- tracks$popularity[match(names(my),tracks$id)]
pick <- sapply(c(TRUE,FALSE),function(k) {i <- which(kinds==k); i[which.max(popular[i])]})
who <- c(partners[pick[1]],ego,partners[pick[2]])
songs <- tracks$name[match(names(my)[pick],tracks$id)]
pdf("H1/paired_network.pdf",width=11,height=4)
par(mfrow=c(2,1),mar=c(1,1,2,1))
for (bipartite in c(FALSE,TRUE)) {
  plot.new(); plot.window(c(-.5,4.5),c(-1,1))
  title(if (bipartite) "Which recordings connect them?" else "Who collaborated with whom?")
  segments(0,0,4,0,col="grey60")
  points(c(0,2,4),rep(0,3),pch=21,cex=3,bg=c("gold","gold","skyblue"))
  text(c(0,2,4),-.48,artists$name[who])
  if (bipartite) {
    points(c(1,3),c(0,0),pch=22,bg="white",cex=2)
    text(c(1,3),.48,songs,cex=.8)
  }
}
dev.off()
print(data.frame(artist=artists$name[who],superstar=artists$superstar[who]))
print(songs)
