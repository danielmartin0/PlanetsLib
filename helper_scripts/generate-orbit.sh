#bin/bash
env_path=$PWD/.venv
python -m venv $env_path

source $env_path/bin/activate

pip install --upgrade pip
pip install -r requirements.txt
export PROGRAM_NAME="generate-orbit.sh"
python ./generate_orbit_graphics.py $1 $2 $3
