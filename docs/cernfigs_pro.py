import os
BEAM_ROOT = os.environ.get("BEAM_ROOT", ".")  # directory holding temp/{CERN2018,GSI2019}/*_UPSETS.csv (beam data, not included)
import csv, ast, collections
import numpy as np
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

OUT=os.environ.get('DOCS_BUILD', '.')
NAVY='#103a6e'; TEAL='#0078a0'; ORANGE='#b06000'; RED='#c0392b'; BLUE='#2857a4'; GRAY='#8a94a3'
plt.rcParams.update({
 'font.family':'serif','font.serif':['Liberation Serif','DejaVu Serif'],
 'mathtext.fontset':'dejavuserif',
 'font.size':10,'axes.titlesize':10.5,'axes.titleweight':'bold',
 'axes.titlecolor':NAVY,'axes.titlelocation':'left',
 'axes.labelsize':9.5,'xtick.labelsize':8.5,'ytick.labelsize':8.5,
 'axes.edgecolor':'#4a5260','axes.linewidth':0.7,
 'axes.spines.top':False,'axes.spines.right':False,
 'axes.grid':True,'grid.alpha':0.25,'grid.linestyle':'--','grid.linewidth':0.5,
 'axes.axisbelow':True,'legend.frameon':False,'legend.fontsize':8.5,
 'figure.dpi':150,'savefig.bbox':'tight'})
def style(ax): ax.grid(axis='x',visible=False)

FIELDS=['time_tag','time_tag2','readback_capture','is_angled','golden_bit_value','frame_address','frame_index','block_type','top_bot','row_address','column_address','minor_address','word_of_frame','bit_word','bit_frame','masked_bit','masked_frame','essential_bit','non_essential_frame','logic_block','specific_logic','specific_logic_2']
def load(path, header=True):
    rows=[]
    with open(path) as f:
        rd=csv.DictReader(f) if header else csv.DictReader(f,fieldnames=FIELDS)
        for r in rd:
            if r['block_type']=='CLB': rows.append(r)
    return rows
cern=load(os.path.join(BEAM_ROOT, 'temp/CERN2018/CERN2018_UPSETS.csv'))
gsi =load(os.path.join(BEAM_ROOT, 'temp/GSI2019/GSI2019_UPSETS.csv'),header=False)

def analyze(rows):
    groups=collections.defaultdict(list); dir0=dir1=0
    for r in rows:
        groups[(r['time_tag'],r['frame_index'])].append(r)
        if r['golden_bit_value']=='0': dir0+=1
        else: dir1+=1
    sbu=mbu=0; dist2=collections.Counter(); mba=collections.defaultdict(collections.Counter)
    for v in groups.values():
        n=len(v); mba[v[0]['is_angled']][min(n,6)]+=1
        if n==1: sbu+=1
        else: mbu+=1
        if n==2:
            b=sorted(int(x['bit_frame']) for x in v); dist2[b[1]-b[0]]+=1
    return dict(sbu=sbu,mbu=mbu,dir0=dir0,dir1=dir1,dist2=dist2,mba=mba)
c=analyze(cern); g=analyze(gsi)

def bl(ax,xs,vals,fmt='{:,}',dy=0.02):
    m=max(vals)
    for x,v in zip(xs,vals):
        if v: ax.text(x,v,fmt.format(v),ha='center',va='bottom',fontsize=7.5,color='#333')

# ---- 1 SBU vs MBU ----
fig,ax=plt.subplots(figsize=(4.8,3.0)); x=np.arange(2)
ax.bar(x-0.19,[c['sbu'],g['sbu']],0.36,label='SBU events',color=NAVY)
ax.bar(x+0.19,[c['mbu'],g['mbu']],0.36,label='MBU events',color=TEAL)
ax.set_xticks(x,['CERN 2018','GSI 2019']); ax.set_ylabel('events (CLB)')
ax.set_title('Single- vs multi-bit upset events'); ax.legend(); style(ax)
bl(ax,x-0.19,[c['sbu'],g['sbu']]); bl(ax,x+0.19,[c['mbu'],g['mbu']])
fig.savefig(OUT+'/fig_sbu_mbu.pdf'); plt.close(fig)

# ---- 2 MBU distance ----
d=c['dist2']; buckets=collections.OrderedDict([('1',0),('2--4',0),('5--16',0),('17--64',0),('65--256',0),('$>$256',0)])
for k,v in d.items():
    if k==1: buckets['1']+=v
    elif k<=4: buckets['2--4']+=v
    elif k<=16: buckets['5--16']+=v
    elif k<=64: buckets['17--64']+=v
    elif k<=256: buckets['65--256']+=v
    else: buckets['$>$256']+=v
fig,ax=plt.subplots(figsize=(5.4,3.0))
xs=range(len(buckets)); ax.bar(xs,list(buckets.values()),color=[RED]+[TEAL]*5,width=0.62)
ax.set_yscale('log'); ax.set_xticks(list(xs),list(buckets.keys()))
ax.set_ylabel('two-bit MBU events'); ax.set_xlabel(r'intra-frame bit distance $\Delta b$')
ax.set_title('CERN 2018 (CLB): two-bit MBU intra-frame separation'); style(ax)
for i,v in enumerate(buckets.values()):
    if v: ax.text(i,v*1.12,f'{v:,}',ha='center',fontsize=7.5,color='#333')
fig.savefig(OUT+'/fig_mbu_distance.pdf'); plt.close(fig)

# ---- 3 multiplicity ----
mn=c['mba']['False']; ma=c['mba']['True']; xs=[1,2,3,4,5,6]
def norm(cnt):
    t=sum(cnt.values()) or 1; return [100*cnt.get(x,0)/t for x in xs]
fig,ax=plt.subplots(figsize=(5.4,3.0)); w=0.36
ax.bar([x-w/2 for x in xs],norm(mn),w,label='normal incidence',color=NAVY)
ax.bar([x+w/2 for x in xs],norm(ma),w,label=r'angled (45$^\circ$)',color=ORANGE)
ax.set_xticks(xs,['1','2','3','4','5',r'$\geq$6']); ax.set_yscale('log')
ax.set_ylabel(r'\% of upset events'.replace('\\%','%')); ax.set_xlabel('event multiplicity (bits per frame per readback)')
ax.set_title('CERN 2018 (CLB): upset multiplicity vs beam angle'); ax.legend(); style(ax)
fig.savefig(OUT+'/fig_multiplicity.pdf'); plt.close(fig)

# ---- 4 direction ----
fig,ax=plt.subplots(figsize=(4.4,3.0)); x=np.arange(2)
ax.bar(x-0.19,[c['dir0'],g['dir0']],0.36,label=r'0$\rightarrow$1',color=TEAL)
ax.bar(x+0.19,[c['dir1'],g['dir1']],0.36,label=r'1$\rightarrow$0',color=ORANGE)
ax.set_xticks(x,['CERN 2018','GSI 2019']); ax.set_ylabel('erroneous bits (CLB)')
ax.set_title('Bit-flip direction asymmetry'); ax.legend(); style(ax)
bl(ax,x-0.19,[c['dir0'],g['dir0']]); bl(ax,x+0.19,[c['dir1'],g['dir1']])
fig.savefig(OUT+'/fig_direction.pdf'); plt.close(fig)

# ---- 5/6/7 column, word, heatmap ----
col=collections.Counter(); word=collections.Counter(); heat=collections.Counter()
for r in cern:
    try:
        col[int(r['column_address'])]+=1; word[int(r['word_of_frame'])]+=1
        heat[(int(r['row_address']),int(r['column_address']))]+=1
    except: pass
fig,ax=plt.subplots(figsize=(6.4,2.7))
xs=sorted(col); cut={62,63,66}
ax.bar(xs,[col[x] for x in xs],color=[ORANGE if x in cut else NAVY for x in xs],width=0.85)
ax.set_xlabel('column (major) address'); ax.set_ylabel('CLB upsets'); ax.margins(x=0.01)
ax.set_title('CERN 2018: upset count per device column'); style(ax)
ax.annotate('CUT columns 62/63/66',xy=(63,4100),xytext=(40,3800),fontsize=8,color=ORANGE,
            arrowprops=dict(arrowstyle='-|>',color=ORANGE,lw=0.8))
fig.savefig(OUT+'/fig_column.pdf'); plt.close(fig)

fig,ax=plt.subplots(figsize=(6.4,2.6))
xs=sorted(word); ys=[word[x] for x in xs]
ax.plot(xs,ys,color=NAVY,lw=1.2); ax.fill_between(xs,ys,color=NAVY,alpha=0.12)
ax.set_xlabel('word within frame (0--100)'); ax.set_ylabel('CLB upsets'); ax.margins(x=0.01)
ax.set_ylim(0,None); ax.set_title('CERN 2018: upset count per word position in the frame')
fig.savefig(OUT+'/fig_word.pdf'); plt.close(fig)

rows=max(r for r,_ in heat)+1; cols=max(cc for _,cc in heat)+1
M=np.zeros((rows,cols))
for (r_,c_),v in heat.items(): M[r_,c_]=v
fig,ax=plt.subplots(figsize=(6.4,2.4))
im=ax.imshow(M,aspect='auto',origin='lower',cmap='magma')
ax.set_xlabel('column (major) address'); ax.set_ylabel('row'); ax.grid(False)
ax.set_yticks(range(rows)); ax.set_title('CERN 2018: spatial density of CLB upsets')
cb=fig.colorbar(im,ax=ax,fraction=0.035,pad=0.02); cb.set_label('upsets',fontsize=8.5); cb.outline.set_linewidth(0.5)
fig.savefig(OUT+'/fig_heatmap.pdf'); plt.close(fig)

# ---- 8 vectors ----
vecs=[]
with open(os.path.join(BEAM_ROOT, 'temp/CERN2018/CERN2018_distances_passed.block_type=CLB.is_angled=False.csv')) as f:
    for row in csv.reader(f):
        if len(row)>=2: vecs.append((ast.literal_eval(row[0]),int(row[1])))
vecs=vecs[:12]
fig,ax=plt.subplots(figsize=(6.2,2.9))
labels=[f'({int(v[0])},{int(v[1])})' for v,_ in vecs]; vals=[n for _,n in vecs]
cols_=[RED if abs(v[0])<=1 and abs(v[1])<=1 else (ORANGE if v[0]==0 and v[1] in (16,32) else TEAL) for v,_ in vecs]
ax.bar(range(len(vals)),vals,color=cols_,width=0.62); ax.set_yscale('log')
ax.set_xticks(range(len(vals)),labels,rotation=45,ha='right')
ax.set_ylabel('pair occurrences'); ax.set_xlabel(r'displacement vector $(\Delta b,\ \Delta f)$')
ax.set_title('CERN 2018 (CLB): recurring upset displacement vectors'); style(ax)
for i,v in enumerate(vals): ax.text(i,v*1.12,f'{v:,}',ha='center',fontsize=7,color='#333')
fig.savefig(OUT+'/fig_vectors.pdf'); plt.close(fig)

# ---- 9 atlas ----
pats=[]
with open(os.path.join(BEAM_ROOT, 'temp/CERN2018/CERN2018_paterns.block_type=CLB.is_angled=False.csv')) as f:
    for row in csv.reader(f):
        pats.append((int(row[1]),[ast.literal_eval(p) for p in row[2:]]))
pats=sorted(pats,key=lambda x:-x[0])[:6]
fig,axes=plt.subplots(1,6,figsize=(8.6,1.9))
for ax,(cnt,pts) in zip(axes,pats):
    xs=[p[0] for p in pts]; ys=[p[1] for p in pts]
    mx=max(max(xs)+1,2); my=max(max(ys)+1,2)
    ax.set_xlim(-0.5,mx-0.5); ax.set_ylim(-0.5,my-0.5); ax.set_aspect('equal'); ax.invert_yaxis()
    ax.grid(False); ax.set_xticks([]); ax.set_yticks([])
    for sp in ax.spines.values(): sp.set_visible(True); sp.set_linewidth(0.6); sp.set_color('#4a5260')
    for gx in range(mx+1): ax.axvline(gx-0.5,color='#d5d9df',lw=0.5)
    for gy in range(my+1): ax.axhline(gy-0.5,color='#d5d9df',lw=0.5)
    for p in pts:
        ax.add_patch(Rectangle((p[0]-0.5,p[1]-0.5),1,1,color=BLUE if p[2]==1 else RED))
    ax.set_title(f'{cnt:,}',fontsize=9,color=NAVY)
fig.suptitle('Most frequent upset patterns (x: bit offset, y: frame offset; red: golden 0, blue: golden 1)',
             fontsize=9,color=NAVY,fontweight='bold',y=1.06)
fig.savefig(OUT+'/fig_atlas.pdf'); plt.close(fig)

# ---- 10 timeseries ----
def series(rows):
    d=collections.Counter()
    for r in rows:
        try: d[float(r['time_tag'])]+=1
        except: pass
    ts=sorted(d); t0=ts[0]
    return [(t-t0)/60 for t in ts], np.cumsum([d[t] for t in ts])
xc,yc=series(cern); xg,yg=series(gsi)
fig,axes=plt.subplots(1,2,figsize=(7.6,2.7))
axes[0].plot(xc,yc,color=NAVY,lw=1.3); axes[0].set_title('CERN 2018')
axes[1].plot(xg,yg,color=ORANGE,lw=1.3); axes[1].set_title('GSI 2019')
for ax in axes:
    ax.set_xlabel('time since first readback (min)'); ax.set_ylabel('cumulative CLB upset bits')
    ax.yaxis.set_major_formatter(lambda v,_: f'{int(v):,}')
fig.tight_layout()
fig.savefig(OUT+'/fig_timeseries.pdf'); plt.close(fig)
print('10 figures written as PDF')
