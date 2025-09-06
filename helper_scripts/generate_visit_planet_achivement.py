import os

import argparse

from lib.achivement_icon_generator import generate_achivement_icon

# Instantiate the parser
parser = argparse.ArgumentParser(prog=os.getenv('PROGRAM_NAME'))

parser.add_argument('path_to_planet_icon', type=ascii,
                    help='path to the planet\'s icon')
args = parser.parse_args()

generate_achivement_icon(args.path_to_planet_icon.removeprefix("'").removesuffix("'"))