"""Run from repository root: python H1/test_h1.py"""
from pathlib import Path
from collections import Counter
from itertools import combinations
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

out = Path(__file__).resolve().parent
data = out.parent / "Prepared Data"
artists = pd.read_csv(data / "artists_clean.csv").set_index("id")
credits = pd.read_csv(data / "artist_track_credits.csv")
tracks = pd.read_csv(data / "tracks_clean.csv").set_index("id")
pairs = Counter()
for tid, group in credits.groupby("track_id"):
    ids = sorted(group.loc[group.superstar.notna(), "artist_id"].unique())
    pairs.update(combinations(ids, 2))
nodes = sorted({i for edge in pairs for i in edge})
index = {a:i for i,a in enumerate(nodes)}
left,right = np.array([(index[a],index[b]) for a,b in pairs]).T
weight = np.array(list(pairs.values()))
star = artists.loc[nodes,"superstar"].astype(int).to_numpy()
degree = np.bincount(np.r_[left,right])
bins = np.searchsorted([1,2,4,8,16,32,64],degree)
strata = [np.where(bins==b)[0] for b in np.unique(bins)]
s,n = star.sum(),len(star)-star.sum()
possible = np.array([n*(n-1)/2,s*n,s*(s-1)/2])
def measure(labels):
    k = labels[left]+labels[right]
    density = np.bincount(k,minlength=3)/possible
    nn,mix,ss = np.bincount(k,weights=weight,minlength=3)
    marginal = (2*ss+mix)/(2*weight.sum())
    r = (ss/weight.sum()-marginal**2)/(marginal*(1-marginal))
    return density[2]-density[1], r
rng = np.random.default_rng(2386)
draws = []
for _ in range(4999):
    labels = star.copy()
    for group in strata:
        labels[group] = rng.permutation(star[group])
    draws.append(measure(labels))
draws = np.array(draws)
obs = np.array(measure(star))
p = (1+(draws>=obs).sum(axis=0))/5000
pd.DataFrame(dict(statistic=["density difference","weighted assortativity"],observed=obs,null_mean=draws.mean(axis=0),p=p)).to_csv(out/"permutation_results.csv",index=False)
k = star[left]+star[right]
dense = np.bincount(k)/possible*10000
table = pd.DataFrame(dict(pair=["Other–other","Mixed","Star–star"],edges=np.bincount(k),possible=possible,per_10000=dense))
table["share_of_all_edges"] = table.edges / len(pairs)
table["possible"] = table.possible.astype(int)
table.loc[len(table)] = ["Total", len(pairs), int(possible.sum()), 10000 * len(pairs) / possible.sum(), 1.0]
table.to_csv(out/"density.csv", index=False)
fig,ax=plt.subplots(figsize=(8,3))
ax.barh(["Other–other","Star–other","Star–star"],dense,color=["#b6c1bf","#648e88","#168060"])
for i,v in enumerate(dense):ax.text(v+.6,i,f"{v:.1f}",va="center",fontsize=12)
ax.set(xlim=(0,53),xlabel="Distinct partnerships per 10,000 possible pairs")
fig.tight_layout();fig.savefig(out/"density.png",dpi=180);plt.close()
fig,axes=plt.subplots(1,2,figsize=(10,3.3))
for j,(ax,title) in enumerate(zip(axes,["Density gap per 10,000 pairs","Weighted status assortativity"])):
    scale=[10000,1][j]
    ax.hist(draws[:,j]*scale,bins=32,color="#82b8ac")
    ax.axvline(obs[j]*scale,color="#933941",lw=3,label=f"Observed {obs[j]*scale:.3g}")
    ax.set(xlabel=title,ylabel="Permutations");ax.legend(frameon=False)
fig.tight_layout();fig.savefig(out/"permutations.png",dpi=180);plt.close()
# Refit the track model. Scores from recordings sharing an artist can covary.
from scipy.stats import norm
known = credits[credits.superstar.notna()].groupby("track_id").artist_id.agg(list)
results=[]
for label,sample in [("Full catalogue",tracks),("Popularity ≥65",tracks[tracks.popularity>=65])]:
    t=sample[sample.collaboration_type.isin(["All superstar","Mixed status"])].copy()
    X=np.column_stack([np.ones(len(t)),t.collaboration_type.eq("All superstar"),t.artist_count,pd.get_dummies(t.year,drop_first=True)]).astype(float)
    y=t.popularity.to_numpy(); coef=np.linalg.lstsq(X,y,rcond=None)[0]
    influence=(X@np.linalg.inv(X.T@X)[:,1])*(y-X@coef)
    membership={}
    for i,ids in enumerate(known.loc[t.index]):
        for artist in ids:membership.setdefault(artist,[]).append(i)
    variance=influence@influence
    for i,ids in enumerate(known.loc[t.index]):
        js={j for artist in ids for j in membership[artist] if j>i}
        variance+=2*influence[i]*sum(influence[j] for j in js)
    se=np.sqrt(variance);v=coef[1]
    results.append((label,len(t),v,v-1.96*se,v+1.96*se,2*norm.sf(abs(v/se))))
result=pd.DataFrame(results,columns=["sample","n","difference","low","high","p"])
result.to_csv(out/"popularity_results.csv",index=False)
fig,ax=plt.subplots(figsize=(8,2.6))
for i,row in result.iterrows():
    ax.errorbar(row.difference,1-i,xerr=row.high-row.difference,fmt="o",capsize=6,ms=9,color="#168060")
    ax.text(row.high+.3,1-i,f"+{row.difference:.2f}",va="center")
ax.axvline(0,color="#888",ls="--");ax.set(yticks=[1,0],yticklabels=result["sample"],ylim=(-.6,1.6),xlim=(-.5,14),xlabel="Adjusted Spotify popularity difference (95% CI)")
fig.tight_layout();fig.savefig(out/"popularity.png",dpi=180);plt.close()
