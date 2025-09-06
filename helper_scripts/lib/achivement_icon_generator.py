import os, sys
from PIL import Image,ImageChops

size = 128, 128


background = Image.open("visit-planet-background.png")
foreground = Image.open("visit-planet-overlay.png")
alpha = Image.open("visit-planet-achievement-frame-alpha.png")
mask = Image.open("visit-planet-achievement-frame-mask.png")

def generate_achivement_icon(source):
    path = os.path.abspath(source)
    outfile = os.path.splitext(path)[0] + "-visit-achivement.png"
    print(outfile)
    print("source:'%s' " % path)
    if path != outfile:
        try:
            im = Image.open(path).resize(size)
            im = ImageChops.offset(im, 25, 33)#.paste(alpha, mask=alpha)

            im = Image.composite(mask,im, alpha)
            back = Image.alpha_composite(background,im)
            Image.alpha_composite(back,foreground).save(outfile, "PNG")
        except IOError:
            print("cannot create achivement icon for for '%s'" % path)
    pass