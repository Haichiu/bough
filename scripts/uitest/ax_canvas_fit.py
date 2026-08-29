#!/usr/bin/env python3
"""U8: derive the visible map canvas from AX and diagnose fit versus centering."""
import argparse
import re
import sys
from collections import defaultdict
from svg_compare import ax_frames, fixture_depths


def read_ax(path):
    rows=[]
    for line in open(path,encoding='utf-8'):
        p=line.rstrip('\n').split('\t',5)
        if len(p)!=6: continue
        try: frame=tuple(map(float,p[1:5]))
        except ValueError: continue
        rows.append((p[0],frame,p[5]))
    return rows


def right(f): return f[0]+f[2]
def bottom(f): return f[1]+f[3]
def area(f): return f[2]*f[3]
def center(f): return (f[0]+f[2]/2,f[1]+f[3]/2)
def inside(outer,inner,tol=1):
    return (inner[0]>=outer[0]-tol and inner[1]>=outer[1]-tol
            and right(inner)<=right(outer)+tol and bottom(inner)<=bottom(outer)+tol)
def fmt(f): return '('+','.join(f'{v:.1f}' for v in f)+')'


def derive_canvas(rows):
    windows=[f for role,f,_ in rows if role=='AXWindow']
    if len(windows)!=1: raise ValueError(f'expected one AXWindow, got {windows}')
    window=windows[0]; wx,wy,ww,wh=window
    groups=[f for role,f,_ in rows if role=='AXGroup' and inside(window,f)]
    if not groups: raise ValueError('no AXGroup contained by window')
    max_group=max(groups,key=area)
    toolbars=[f for role,f,_ in rows if role=='AXToolbar' and inside(window,f)
              and f[2]>=ww*.8 and f[1]<wy+wh*.35]
    if len(toolbars)!=1: raise ValueError(f'expected one full-width AXToolbar, got {toolbars}')
    toolbar=toolbars[0]
    tabbars=[f for role,f,_ in rows if role=='AXScrollArea' and inside(window,f)
             and f[2]>=ww*.75 and f[1]>=bottom(toolbar)-1 and f[1]<wy+wh*.5]
    if not tabbars: raise ValueError('no top wide AXScrollArea for document tab bar')
    tabbar=min(tabbars,key=lambda f:f[1])
    tab_inset=tabbar[1]-bottom(toolbar)
    if not 0<=tab_inset<=20: raise ValueError(f'implausible tab-bar inset {tab_inset}')
    radios=[f for role,f,_ in rows if role=='AXRadioGroup' and inside(window,f)
            and f[0]>=wx+ww*.5]
    if len(radios)!=1: raise ValueError(f'expected one right-side AXRadioGroup, got {radios}')
    inspector_tabs=radios[0]
    right_inset=right(window)-right(inspector_tabs)
    if not 0<=right_inset<=ww*.1: raise ValueError(f'implausible inspector inset {right_inset}')
    inspector_left=inspector_tabs[0]-right_inset
    # The tab ScrollArea excludes the VStack's symmetric vertical padding. Its
    # top gap from the toolbar therefore supplies the same bottom inset.
    top=bottom(tabbar)+tab_inset
    canvas=(wx,top,inspector_left-wx,bottom(window)-top)
    if canvas[2]<=0 or canvas[3]<=0: raise ValueError(f'non-positive canvas {canvas}')
    return window,max_group,toolbar,tabbar,tab_inset,inspector_tabs,canvas


def union(frames):
    x=min(f[0] for f in frames); y=min(f[1] for f in frames)
    r=max(right(f) for f in frames); b=max(bottom(f) for f in frames)
    return (x,y,r-x,b-y)


def probe_geo(rows):
    probes=[value for role,_,value in rows if role=='AXStaticText' and value.startswith('canvasprobe')]
    if not probes: return None
    if len(probes)!=1: raise ValueError(f'expected at most one canvasprobe, got {len(probes)}')
    m=re.match(r'canvasprobe geo=([-.0-9]+),([-.0-9]+) ',probes[0])
    if not m: raise ValueError(f'malformed canvasprobe: {probes[0]}')
    return (float(m.group(1)),float(m.group(2)))


def main():
    p=argparse.ArgumentParser(); p.add_argument('ax_tsv'); p.add_argument('fixture')
    p.add_argument('--tolerance',type=float,default=1.0,
                   help='provisional integer-AX boundary allowance in points')
    p.add_argument('--center-tolerance',type=float,default=3.1,
                   help='AX text-vs-card center basis allowance in points')
    a=p.parse_args()
    try:
        depths=fixture_depths(a.fixture); root=next(t for t,d in depths.items() if d==0)
        nodes=ax_frames(a.ax_tsv,depths,root)
        missing=sorted(set(depths)-set(nodes))
        if missing: raise ValueError(f'missing fixture nodes in AX: {missing}')
        rows=read_ax(a.ax_tsv)
        window,max_group,toolbar,tabbar,tab_inset,inspector,canvas=derive_canvas(rows)
        geo=probe_geo(rows)
    except ValueError as error:
        print(f'FAIL U8: {error}'); return 1

    bbox=union(list(nodes.values())); cc=center(canvas); bc=center(bbox)
    dx,dy=bc[0]-cc[0],bc[1]-cc[1]
    margins={'left':bbox[0]-canvas[0], 'top':bbox[1]-canvas[1],
             'right':right(canvas)-right(bbox), 'bottom':bottom(canvas)-bottom(bbox)}
    violations=[]; touches=[]
    for text,frame in nodes.items():
        overflow={'left':canvas[0]-frame[0], 'top':canvas[1]-frame[1],
                  'right':right(frame)-right(canvas), 'bottom':bottom(frame)-bottom(canvas)}
        bad={side:value for side,value in overflow.items() if value>a.tolerance}
        if bad: violations.append((text,bad))
        edges={'left':abs(frame[0]-canvas[0]), 'top':abs(frame[1]-canvas[1]),
               'right':abs(right(frame)-right(canvas)), 'bottom':abs(bottom(frame)-bottom(canvas))}
        hit=[side for side,value in edges.items() if value<=a.tolerance]
        if hit: touches.append((text,hit))

    beyond=[]
    for role,frame,value in rows:
        over_r=right(frame)-right(canvas); over_b=bottom(frame)-bottom(canvas)
        if over_r>a.tolerance or over_b>a.tolerance: beyond.append((role,over_r,over_b))
    summary=defaultdict(lambda:[0,0.0,0.0])
    for role,over_r,over_b in beyond:
        summary[role][0]+=1; summary[role][1]=max(summary[role][1],over_r); summary[role][2]=max(summary[role][2],over_b)

    size_fits=bbox[2]<=canvas[2]+a.tolerance and bbox[3]<=canvas[3]+a.tolerance
    centered=abs(dx)<=a.center_tolerance and abs(dy)<=a.center_tolerance
    fully_inside=not violations
    geo_ok=geo is None or (abs(geo[0]-canvas[2])<=a.tolerance and abs(geo[1]-canvas[3])<=a.tolerance)
    print(f'U8 raw AXWindow={fmt(window)} max-AXGroup={fmt(max_group)} AXToolbar={fmt(toolbar)} top-AXScrollArea={fmt(tabbar)} tabInset={tab_inset:.1f} right-AXRadioGroup={fmt(inspector)}')
    print(f'U8 canvas={fmt(canvas)} fixture_bbox={fmt(bbox)} nodes={len(nodes)} n_labels={sum(t.startswith("N-") for t in nodes)}')
    print(f'U8 size content={bbox[2]:.1f}x{bbox[3]:.1f} canvas={canvas[2]:.1f}x{canvas[3]:.1f} fits={size_fits}')
    print(f'U8 center content=({bc[0]:.1f},{bc[1]:.1f}) canvas=({cc[0]:.1f},{cc[1]:.1f}) delta=({dx:+.1f},{dy:+.1f}) centered={centered} tolerance={a.center_tolerance:.1f}')
    print('U8 margins '+ ' '.join(f'{k}={v:.1f}' for k,v in margins.items())
          +f' edge_touch={bool(touches)} extent_known=True boundary_tolerance={a.tolerance:.1f} (single observation; provisional)')
    if geo is None: print('U8 probe-selfcheck=unavailable (diagnostic probe absent)')
    else: print(f'U8 probe-geo={geo[0]:.1f}x{geo[1]:.1f} derived={canvas[2]:.1f}x{canvas[3]:.1f} match={geo_ok}')
    if touches: print('U8 edge-touch '+ '; '.join(f'{text}:{"/".join(sides)}' for text,sides in touches))
    if summary: print('U8 beyond-canvas '+ ' '.join(f'{role}:count={v[0]},maxRight={v[1]:.1f},maxBottom={v[2]:.1f}' for role,v in sorted(summary.items())))
    if violations: print('U8 fixture-beyond '+ '; '.join(f'{text}:'+','.join(f'{k}={v:.1f}' for k,v in bad.items()) for text,bad in violations[:8]))
    if fully_inside and size_fits and centered and geo_ok:
        print('PASS U8'); return 0
    print(f'FAIL U8: inside={fully_inside} size_fits={size_fits} centered={centered} probe_geometry={geo_ok}')
    return 1


if __name__=='__main__': sys.exit(main())
