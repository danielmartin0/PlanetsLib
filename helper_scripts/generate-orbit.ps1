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
$env:PROGRAM_NAME = "generate-orbit.sh"

# Run the Python script with up to three arguments
py ./generate_orbit_graphics.py $args[0] $args[1] $args[2]