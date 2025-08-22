from lib.orbit_graphic_generator import generate_orbit
import os

import argparse
# Instantiate the parser
parser = argparse.ArgumentParser(prog=os.getenv('PROGRAM_NAME'))

parser.add_argument('distance', type=float,
                    help='distance from the parent')

parser.add_argument('planet_name', type=ascii,
                    help='name of the planet the orbit belongs to')

parser.add_argument('mod_name', type=ascii,
                    help='name of the mod the planet belongs to')
args = parser.parse_args()

generate_orbit(args.distance, "orbit-"+args.planet_name.removeprefix("'").removesuffix("'")+".png",args.mod_name.removeprefix("'").removesuffix("'"))

