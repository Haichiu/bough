#!/usr/bin/env python3
"""Compare AX frames with SVG geometry and the accepted NodeStyle contract.

Absolute coordinates are ignored because screen and SVG use different origins and
viewport transforms. Provisional tolerances are evidence-derived from the one saved
capture: position 0.016, width-profile 0.083 (about 4x observed error), and
height-profile 0.02 (provisional because observed error was zero).
"""
import argparse
import json
import math
import statistics
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict, deque


def number(value):
    try: return float(value)
    except (TypeError, ValueError): return None


def local(tag): return tag.rsplit('}', 1)[-1]

def ordered(values):
    return sorted(values,key=lambda v:(v is None,0 if v is None else v))


def fixture_depths(path):
    doc=json.load(open(path,encoding='utf-8')); q=deque([(doc['root'],0)]); out={}
    while q:
        node,depth=q.popleft(); text=node.get('text','')
        if text in out: raise ValueError(f'fixture text must be unique: {text!r}')
        out[text]=depth; q.extend((c,depth+1) for c in node.get('children',[]))
    return out


def ax_frames(path,wanted,root_text):
    candidates=defaultdict(list); frame_values=defaultdict(set)
    for line in open(path,encoding='utf-8'):
        p=line.rstrip('\n').split('\t',5)
        if len(p)!=6 or p[0]!='AXStaticText': continue
        frame=tuple(map(float,p[1:5])); frame_values[frame].add(p[5])
        if p[5] in wanted: candidates[p[5]].append(frame)

    unexpected={text:frames for text,frames in candidates.items()
                if text!=root_text and len(frames)>1}
    if unexpected:
        detail=', '.join(f'{text!r} x{len(frames)}' for text,frames in unexpected.items())
        raise ValueError(f'duplicate AX node label is not the document title: {detail}')

    out={text:frames[0] for text,frames in candidates.items() if len(frames)==1}
    roots=candidates.get(root_text,[])
    if len(roots)>1:
        # The window title equals the root text. In this AX tree its title-bar
        # frame is also occupied by the version/autosave status text; the canvas
        # root is the sole remaining candidate. Fail closed if that structure
        # changes rather than silently choosing by size or order.
        title=[frame for frame in roots if frame_values[frame]-{root_text}]
        canvas=[frame for frame in roots if frame not in title]
        if len(title)!=1 or len(canvas)!=1:
            raise ValueError(f'ambiguous document-title/root candidates: title={title} canvas={canvas}')
        out[root_text]=canvas[0]
    return out


def point(el):
    x,y=number(el.get('x')),number(el.get('y'))
    if x is None or y is None:
        for c in el:
            x=x if x is not None else number(c.get('x'))
            y=y if y is not None else number(c.get('y'))
    return x,y


def svg_nodes(path,wanted):
    root=ET.parse(path).getroot(); elements=list(root.iter())
    rects=[]
    for i,el in enumerate(elements):
        if local(el.tag)!='rect': continue
        vals=tuple(number(el.get(k)) for k in ('x','y','width','height'))
        if None not in vals: rects.append((i,el,vals))

    grouped=defaultdict(list)
    for i,el in enumerate(elements):
        if local(el.tag)!='text': continue
        text=''.join(el.itertext()).strip(); x,y=point(el)
        if not text or x is None or y is None: continue
        containing=[]
        for ri,rect,(rx,ry,rw,rh) in rects:
            if rx<=x<=rx+rw and ry<=y<=ry+rh+1:
                containing.append((rw*rh,ri,rect,(rx,ry,rw,rh)))
        if containing:
            _,ri,rect,frame=min(containing)
            line_count=max(1,sum(1 for c in el if local(c.tag)=='tspan'))
            grouped[ri].append((i,text,el,rect,frame,line_count))

    out={}
    for rows in grouped.values():
        rows.sort(); combined=''.join(r[1] for r in rows)
        if combined not in wanted: continue
        _,_,first,rect,frame,_=rows[0]
        fonts={number(r[2].get('font-size')) for r in rows}
        out[combined]={
            'frame':frame, 'fonts':fonts, 'rx':number(rect.get('rx')),
            'line_count':sum(r[5] for r in rows),
            'fill':rect.get('fill'), 'fill_opacity':number(rect.get('fill-opacity')),
            'stroke':rect.get('stroke'), 'stroke_opacity':number(rect.get('stroke-opacity')),
            'stroke_width':number(rect.get('stroke-width')),
        }
    return out


def normalized_centers(frames):
    c={k:(v[0]+v[2]/2,v[1]+v[3]/2) for k,v in frames.items()}
    xs=[v[0] for v in c.values()]; ys=[v[1] for v in c.values()]
    sx=max(max(xs)-min(xs),1); sy=max(max(ys)-min(ys),1)
    return {k:((x-min(xs))/sx,(y-min(ys))/sy) for k,(x,y) in c.items()}


def profile_error(ax,svg,depths,dim):
    groups=defaultdict(list)
    for name in ax: groups[depths[name]].append(name)
    errors=[]
    for names in groups.values():
        am=statistics.median(ax[n][dim] for n in names)
        sm=statistics.median(svg[n]['frame'][dim] for n in names)
        errors.extend(abs(ax[n][dim]/am-svg[n]['frame'][dim]/sm) for n in names)
    return max(errors,default=0)


def main():
    p=argparse.ArgumentParser(); p.add_argument('ax_tsv'); p.add_argument('svg'); p.add_argument('fixture')
    p.add_argument('--fonts',default='18,15,13'); p.add_argument('--radii',default='14,11,9')
    p.add_argument('--root-fill',default='#3c4c62')
    p.add_argument('--deep-fill-opacity',type=float,default=.12)
    p.add_argument('--deep-stroke-opacity',type=float,default=.38)
    p.add_argument('--deep-stroke-width',type=float,default=1)
    p.add_argument('--position-tolerance',type=float,default=.016)
    p.add_argument('--width-tolerance',type=float,default=.083)
    p.add_argument('--height-tolerance',type=float,default=.02); a=p.parse_args()
    expected_fonts=list(map(float,a.fonts.split(','))); expected_radii=list(map(float,a.radii.split(',')))
    try:
        depths=fixture_depths(a.fixture)
        root_text=next(text for text,depth in depths.items() if depth==0)
        ax=ax_frames(a.ax_tsv,depths,root_text); svg=svg_nodes(a.svg,depths)
    except ValueError as error:
        print(f'FAIL U7: {error}'); return 1
    missing_ax=sorted(set(depths)-set(ax)); missing_svg=sorted(set(depths)-set(svg))
    if missing_ax or missing_svg:
        print(f'FAIL U7: mapping missing_ax={missing_ax} missing_svg={missing_svg}'); return 1

    na=normalized_centers(ax); ns=normalized_centers({k:v['frame'] for k,v in svg.items()})
    pos=max(math.hypot(na[n][0]-ns[n][0],na[n][1]-ns[n][1]) for n in depths)
    we=profile_error(ax,svg,depths,2); he=profile_error(ax,svg,depths,3)
    geometry_ok=(pos<=a.position_tolerance and we<=a.width_tolerance
                 and he<=a.height_tolerance)

    style_ok=True
    for depth in (0,1,2):
        names=[n for n,d in depths.items() if min(d,2)==depth]
        fonts=ordered({f for n in names for f in svg[n]['fonts']})
        radii=ordered({svg[n]['rx'] for n in names})
        ok=fonts==[expected_fonts[depth]] and radii==[expected_radii[depth]]
        style_ok &= ok
        note=' (source consistency only; old exporter also used 9)' if depth==2 else ''
        print(f'U7 depth={depth} font={fonts} want={[expected_fonts[depth]]} rx={radii} want={[expected_radii[depth]]}{note}')

    shallow=[n for n,d in depths.items() if d<2]
    root=[n for n,d in depths.items() if d==0]
    shallow_ok=(all(svg[n]['fill_opacity']==1.0 and svg[n]['stroke']=='none' for n in shallow)
                and len(root)==1 and svg[root[0]]['fill']==a.root_fill)
    deep=[n for n,d in depths.items() if d>=2]
    fill_ops=ordered({svg[n]['fill_opacity'] for n in deep})
    stroke_ops=ordered({svg[n]['stroke_opacity'] for n in deep})
    stroke_widths=ordered({svg[n]['stroke_width'] for n in deep})
    stroke_matches_fill=all(svg[n]['stroke']==svg[n]['fill'] for n in deep)
    paint_ok=(fill_ops==[a.deep_fill_opacity] and stroke_ops==[a.deep_stroke_opacity]
              and stroke_widths==[a.deep_stroke_width] and stroke_matches_fill)
    longest=max(deep,key=len); wrap_lines=svg[longest]['line_count']; wrap_ok=wrap_lines>=2
    print(f'U7 geometry position_error={pos:.4f}/{a.position_tolerance} width_profile={we:.4f}/{a.width_tolerance} height_profile={he:.4f}/{a.height_tolerance}')
    print(f'U7 shallow-paint fill-opacity=1 stroke=none root-fill={a.root_fill} ok={shallow_ok}')
    print(f'U7 deep-paint fill-opacity={fill_ops} stroke-opacity={stroke_ops} stroke-width={stroke_widths} stroke-matches-fill={stroke_matches_fill}')
    print(f'U7 wrapping node_chars={len(longest)} svg_lines={wrap_lines} want>=2')
    if geometry_ok and style_ok and shallow_ok and paint_ok and wrap_ok:
        print('PASS U7'); return 0
    print(f'FAIL U7: geometry_ok={geometry_ok} style_ok={style_ok} shallow_ok={shallow_ok} paint_ok={paint_ok} wrap_ok={wrap_ok}')
    return 1


if __name__=='__main__': sys.exit(main())
