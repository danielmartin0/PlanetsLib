# Set virtual environment path
$envPath = "$PWD\.venv"

# Create virtual environment
py -m venv $envPath

# Activate virtual environment (Windows-style path)
& "$envPath\Scripts\Activate.ps1"

# Upgrade pip
py -m pip install --upgrade pip

# Install dependencies
py -m pip install -r requirements.txt

# Set environment variable
$env:PROGRAM_NAME = "planet-achivement.ps1"

# Run the Python script with up to three arguments
py ./generate_visit_planet_achivement.py $args[0]