#bin/bash
env_path=$PWD/.venv
python -m venv $env_path

source $env_path/bin/activate

pip install --upgrade pip
pip install -r requirements.txt
export PROGRAM_NAME="generate-planet-achivement.sh"
python ./generate_visit_planet_achivement.py $1
