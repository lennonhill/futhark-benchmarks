#!/usr/bin/env python3

import sys
import os
import math
import png
import numpy as np


def n_digits(n_elems):
    return int(math.log(n_elems, 10)) + 1

def main(args):
    try:
        out_dir = args[0]
    except IndexError:
        print('error: output directory must be given as the first argument',
              file=sys.stderr)
        return 1
    try:
        os.makedirs(out_dir)
    except IOError:
        print('error: output directory already exists',
              file=sys.stderr)
        return 1

    try:
        backend_format = args[1]
    except IndexError:
        print('error: the backend format ("futhark" or "c") must be given as the second argument',
              file=sys.stderr)
        return 1
    if backend_format not in ['futhark', 'c']:
        print('error: the backend format must be "futhark" or "c"',
              file=sys.stderr)
        return 1

    if backend_format == 'futhark':
        images = np.array(eval(sys.stdin.read().replace('i32', '')))
    elif backend_format == 'c':
        lines = sys.stdin.read().strip().split('\n')
        N = int(lines[0])
        images = [np.array([int(n) for n in line.strip().split(' ')]).reshape((N, N))
                  for line in lines[1:]]

    for image, i in zip(images, range(len(images))):
        filename = os.path.join(
            out_dir,
            ('fluid_{:0' + str(max(8, n_digits(len(images)))) + 'd}.png').format(i))
        with open(filename, 'wb') as f:
            w = png.Writer(image.shape[1], image.shape[0], greyscale=True, bitdepth=8)
            w.write(f, image)

    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))