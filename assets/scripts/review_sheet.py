"""Compose the review sheet from the ten product renders (Pillow and DejaVu)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageStat

renders = Path(__file__).resolve().parents[1] / 'renders'
font_dir = Path('/usr/share/fonts/truetype/dejavu')
def font(name, size):
    return ImageFont.truetype(str(font_dir / (name + '.ttf')), size)

canvas = Image.new('RGB', (1600, 1350), '#f2f0eb')
draw = ImageDraw.Draw(canvas)
dark = '#24313a'
muted = '#556168'
background = tuple(round(v) for v in ImageStat.Stat(
    Image.open(renders/'front.png').convert('RGB').crop((0,0,20,20))).mean)

def label(x,y,text,size=20,color=dark,face='DejaVuSans'):
    draw.text((x,y),text,font=font(face,size),fill=color,anchor='lt')

def fit(name, box):
    im = Image.open(renders/(name+'.png')).convert('RGB')
    if name in ('left', 'right'):
        mid=im.width//2
        im=im.crop((mid-105,0,mid+105,im.height))
    x,y,w,h=box
    im.thumbnail((w,h), Image.Resampling.LANCZOS)
    canvas.paste(im, (x+(w-im.width)//2,y+(h-im.height)//2))

label(60,43,'NanoDesk   /   Model review 01',23,muted)
label(60,90,'iPod nano',70,dark,'DejaVuSerif')
label(455,126,'Fifth generation  ·  A1320  ·  Silver',28)
label(1190,53,'ENCLOSURE',17,muted)
label(1190,89,'38.7 × 90.7 × 6.2 mm',28)
label(1190,135,'Width × height × depth',19,muted)
draw.line((60,194,1540,194), fill='#afb3b1', width=2)
draw.rounded_rectangle((60,254,1540,817),18,fill=background)
# The four elevations share their image height and orthographic scale.
cols=[('front','Front',60,342),('back','Rear',342,624),('left','Left',624,767),
      ('right','Right',767,910),('front_45','Front 45°',910,1225),('back_45','Rear 45°',1225,1540)]
for name,caption,x1,x2 in cols:
    label(x1+16,217,caption,21)
    fit(name,(x1+4,263,x2-x1-8,546))
draw.line((60,854,1540,854), fill='#afb3b1', width=2)
for title,x in [('End elevations',60),('Camera and microphone',600),('Dock and jack',1060)]:
    label(x,881,title,25)
for x,w in [(60,515),(600,435),(1060,480)]:
    draw.rounded_rectangle((x,928,x+w,1240),15,fill=background)
fit('top',(69,938,497,140));fit('bottom',(69,1087,497,140))
fit('camera_detail',(611,939,413,290))
fit('dock_detail',(1068,949,464,270))
label(60,1266,'Top above, bottom below',18,muted)
label(600,1266,'Rear lower-left capsule',18,muted)
label(1060,1266,'Recessed 30-pin connector',18,muted)
canvas.save(renders/'review.jpg',quality=94,subsampling=0,optimize=True)
