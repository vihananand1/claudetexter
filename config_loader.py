# config_loader.py
import yaml

def load_config(config_path="/Users/Vihan/Downloads/WindTexter 2-2/WindTexter/Config/config.yaml"):
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)
    return config
