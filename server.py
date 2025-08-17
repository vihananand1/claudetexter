"""
server.py - SIMPLIFIED VERSION WITH AUTO-ENABLED PATH SHARING

WindTexter backend API and message relay server.
Handles sending and receiving messages via email and SMS, message encryption/compression,
storage, and integration with NLP models for auto-reply. Provides REST API endpoints
for client apps to interact with the system.

SIMPLIFIED: All enabled paths are automatically shared - no manual toggle needed.
"""

from flask import Flask, request, jsonify
from typing import List
from transformers import GPT2LMHeadModel, GPT2Tokenizer
import torch
import json
from Config.config_loader import load_config
from datetime import datetime, timezone
from twilio.rest import Client
import smtplib
from email.message import EmailMessage
from Compression.compression import Compressor
from Encryption.encryption import Encryptor, bytes2bits, bits2bytes
from bitarray import bitarray
import secrets
from dotenv import load_dotenv
import os, binascii
import codecs
import uuid
load_dotenv()

# Email credentials for SMTP
SMTP_EMAIL = "windtexter@gmail.com"
SMTP_PASSWORD = "ndiwzmzqxecidfed"

# Flask app setup
app = Flask(__name__)

# Load configuration and defaults
config = load_config()
DEFAULT_COMPRESSION_METHOD = 'utf8'
DEFAULT_ENCRYPTION_MODE = config["encryption"]["cipher_mode"]
DEFAULT_KEY_LENGTH = config["encryption"]["key_length"]

DEFAULT_KEY = b"thisis16byteskey"
DEFAULT_IV = b"initialvector123"

# Create user_configs directory for persistent storage
os.makedirs("user_configs", exist_ok=True)

# Path validation and normalization functions
def normalize_path(path):
    """Normalize path names to consistent format"""
    if not path or not isinstance(path, str):
        print(f"❌ normalize_path: Invalid input - {type(path)}: '{path}'")
        return ""
    
    path_clean = path.lower().strip()
    print(f"🔧 normalize_path: '{path}' -> '{path_clean}'")
    
    # FIXED: More flexible mapping
    if path_clean in ['email', 'send_email', 'gmail']:
        return 'email'
    elif path_clean in ['sms', 'send_sms', 'text', 'message']:
        return 'sms'
    else:
        print(f"🔧 normalize_path: Unknown path '{path_clean}', returning as-is")
        return path_clean

def validate_email(email):
    """Basic email validation"""
    if not email or not isinstance(email, str):
        print(f"❌ validate_email: Invalid input - {type(email)}: '{email}'")
        return False
    email = email.strip().lower()
    is_valid = '@' in email and '.' in email.split('@')[1]
    print(f"✅ validate_email: '{email}' -> {is_valid}")
    return is_valid

def validate_paths(paths):
    """Validate that paths are in allowed list"""
    print(f"\n🔍 === VALIDATE_PATHS DEBUG ===")
    print(f"Input: {paths} (type: {type(paths)})")
    
    if not isinstance(paths, list):
        print(f"❌ Not a list")
        return False
    
    # FIXED: Allow empty arrays (user disabled all paths)
    if len(paths) == 0:
        print(f"✅ Empty list allowed (user disabled all paths)")
        return True
    
    valid_paths = {'email', 'sms'}
    print(f"Valid paths: {valid_paths}")
    
    for i, path in enumerate(paths):
        print(f"  Path {i}: '{path}' (type: {type(path)})")
        
        if not isinstance(path, str):
            print(f"❌ Path {i} not a string")
            return False
        
        normalized = normalize_path(path)
        print(f"  Normalized: '{normalized}'")
        
        if normalized and normalized not in valid_paths:
            print(f"❌ Path '{normalized}' not in valid set")
            return False
        
        print(f"✅ Path {i} valid")
    
    print(f"✅ All paths valid")
    return True

def load_user_path_config(email):
    """Load user's path configuration"""
    try:
        if not validate_email(email):
            print(f"❌ Invalid email for config load: {email}")
            return None
            
        config_file = os.path.join("user_configs", f"{email.strip().lower()}.json")
        print(f"📁 Looking for config file: {config_file}")
        
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                config = json.load(f)
                print(f"📁 Loaded config: {config}")
                
                if not isinstance(config, dict):
                    print(f"❌ Invalid config format")
                    return None
                
                # Normalize paths
                if "enabled_paths" in config:
                    config["enabled_paths"] = [normalize_path(p) for p in config["enabled_paths"]]
                
                return config
        else:
            print(f"📁 No config file found")
            return None
            
    except Exception as e:
        print(f"❌ Error loading config: {e}")
        return None

def save_user_path_config(email, config_data):
    """Save user's path configuration - automatically shared"""
    try:
        if not validate_email(email):
            print(f"❌ Invalid email for config save: {email}")
            return False
            
        if not isinstance(config_data, dict):
            print(f"❌ Invalid config data format")
            return False
        
        os.makedirs("user_configs", exist_ok=True)
        
        email_clean = email.strip().lower()
        config_file = os.path.join("user_configs", f"{email_clean}.json")
        
        # Normalize paths before saving
        if "enabled_paths" in config_data:
            config_data["enabled_paths"] = [normalize_path(p) for p in config_data["enabled_paths"]]
        
        # SIMPLIFIED: Always enable sharing
        config_data["sharing_enabled"] = True
        
        with open(config_file, 'w') as f:
            json.dump(config_data, f, indent=2)
            
        print(f"💾 Saved config to: {config_file}")
        print(f"💾 Config data: {config_data}")
        return True
        
    except Exception as e:
        print(f"❌ Error saving config: {e}")
        return False

def validate_path(delivery_path):
    """Checks if the delivery_path is valid for sending messages"""
    valid_paths = ["email", "sms", "windtexter"]
    normalized = normalize_path(delivery_path)
    return normalized in valid_paths

# SIMPLIFIED ROUTE REGISTRATION
print("🚀 Registering simplified Flask routes...")

@app.route('/disable_user_paths', methods=['POST'])
def disable_user_paths():
    """Handle when user disables all delivery paths"""
    print(f"\n🚫 === DISABLE_USER_PATHS CALLED ===")
    
    try:
        if not request.is_json:
            return jsonify({"error": "Content-Type must be application/json"}), 400
        
        data = request.get_json()
        if not data:
            return jsonify({"error": "No JSON data provided"}), 400
        
        email = data.get("email", "").strip().lower()
        device_id = data.get("device_id", "").strip()
        
        print(f"📧 Disabling paths for email: '{email}'")
        print(f"📱 Device ID: '{device_id}'")
        
        if not validate_email(email):
            return jsonify({"error": "Valid email is required"}), 400
        
        if not device_id:
            return jsonify({"error": "Device ID is required"}), 400
        
        # Create config with empty paths but still enabled sharing
        config_data = {
            "enabled_paths": [],
            "device_id": device_id,
            "last_updated": datetime.now(timezone.utc).isoformat(),
            "sharing_enabled": True  # Still share the fact that no paths are enabled
        }
        
        if save_user_path_config(email, config_data):
            print(f"✅ Successfully disabled all paths")
            return jsonify({
                "status": "disabled",
                "enabled_paths": [],
                "sharing_enabled": True
            })
        else:
            return jsonify({"error": "Failed to save configuration"}), 500
        
    except Exception as e:
        print(f"❌ Exception in disable_user_paths: {e}")
        return jsonify({"error": "Internal server error"}), 500

@app.route('/update_user_path_config', methods=['POST'])
def update_user_path_config():
    """FIXED: Handle path updates with better validation"""
    print(f"\n🔧 === UPDATE_USER_PATH_CONFIG CALLED (FIXED) ===")
    
    try:
        if not request.is_json:
            print("❌ Request is not JSON")
            return jsonify({"error": "Content-Type must be application/json"}), 400
        
        data = request.get_json()
        if not data:
            print("❌ No JSON data received")
            return jsonify({"error": "No JSON data provided"}), 400
        
        print(f"📨 Request data: {data}")
        
        # Extract and validate fields
        email = data.get("email", "").strip().lower()
        enabled_paths = data.get("enabled_paths", [])
        device_id = data.get("device_id", "").strip()
        
        print(f"📧 Email: '{email}'")
        print(f"🛤️  Enabled paths: {enabled_paths}")
        print(f"📱 Device ID: '{device_id}'")
        
        # Validation
        if not validate_email(email):
            print("❌ Invalid email")
            return jsonify({"error": "Valid email is required"}), 400
        
        if not device_id:
            print("❌ Missing device_id")
            return jsonify({"error": "Device ID is required"}), 400
        
        # FIXED: Better path validation
        if not isinstance(enabled_paths, list):
            print(f"❌ enabled_paths is not a list: {type(enabled_paths)}")
            return jsonify({"error": "enabled_paths must be an array"}), 400
        
        # Validate and normalize paths
        print(f"\n🔍 Validating paths: {enabled_paths}")
        if not validate_paths(enabled_paths):
            print(f"❌ Path validation failed")
            return jsonify({"error": f"Invalid paths provided"}), 400
        
        # Normalize paths (filter out empty ones)
        normalized_paths = [normalize_path(p) for p in enabled_paths if p and normalize_path(p)]
        print(f"🔧 Normalized paths: {normalized_paths}")
        
        # Create config with automatic sharing
        config_data = {
            "enabled_paths": normalized_paths,
            "device_id": device_id,
            "last_updated": datetime.now(timezone.utc).isoformat(),
            "sharing_enabled": True  # Always enabled in simplified version
        }
        
        print(f"💾 Saving config: {config_data}")
        
        # Save config
        if save_user_path_config(email, config_data):
            print(f"✅ Successfully saved config")
            return jsonify({
                "status": "updated",
                "normalized_paths": normalized_paths,
                "sharing_enabled": True
            })
        else:
            print(f"❌ Failed to save config")
            return jsonify({"error": "Failed to save configuration"}), 500
        
    except Exception as e:
        print(f"❌ Exception in update_user_path_config: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": "Internal server error"}), 500

print("✅ Registered /update_user_path_config (auto-sharing)")

@app.route('/get_user_path_config', methods=['POST'])
def get_user_path_config():
    """Get user's shared path configuration - always returns paths if they exist"""
    print(f"\n🔍 === GET_USER_PATH_CONFIG CALLED (AUTO-SHARING) ===")
    
    try:
        if not request.is_json:
            print("❌ Request is not JSON")
            return jsonify({"error": "Content-Type must be application/json"}), 400
        
        data = request.get_json()
        if not data:
            print("❌ No JSON data received")
            return jsonify({"error": "No JSON data provided"}), 400
        
        print(f"📨 Request data: {data}")
        
        email = data.get("email", "").strip().lower()
        print(f"📧 Email: '{email}'")
        
        if not validate_email(email):
            print("❌ Invalid email")
            return jsonify({"error": "Valid email is required"}), 400
        
        # Load config
        config = load_user_path_config(email)
        
        if config and config.get("enabled_paths"):
            enabled_paths = config.get("enabled_paths", [])
            last_updated = config.get("last_updated")
            
            # Normalize paths
            normalized_paths = [normalize_path(p) for p in enabled_paths]
            
            print(f"✅ Found auto-shared config: {normalized_paths}")
            
            return jsonify({
                "enabled_paths": normalized_paths,
                "last_updated": last_updated,
                "sharing_enabled": True
            })
        else:
            print(f"🚫 No paths configured for this user")
            return jsonify({"enabled_paths": []})
        
    except Exception as e:
        print(f"❌ Exception in get_user_path_config: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": "Internal server error"}), 500

print("✅ Registered /get_user_path_config (auto-sharing)")

# Debug endpoints
@app.route('/test_path_validation', methods=['POST'])
def test_path_validation():
    """Debug endpoint to test path validation"""
    try:
        data = request.get_json()
        paths = data.get("paths", [])
        
        print(f"🧪 Testing path validation for: {paths}")
        
        result = {
            "input_paths": paths,
            "input_type": str(type(paths)),
            "is_valid": validate_paths(paths),
            "normalized": [normalize_path(p) for p in paths] if isinstance(paths, list) else [],
            "valid_paths": ['email', 'sms']
        }
        
        print(f"🧪 Test result: {result}")
        return jsonify(result)
        
    except Exception as e:
        print(f"❌ Error in test endpoint: {e}")
        return jsonify({"error": str(e)}), 500

print("✅ Registered /test_path_validation")

@app.route('/debug_routes', methods=['GET'])
def debug_routes():
    """Debug endpoint to list all registered routes"""
    routes = []
    for rule in app.url_map.iter_rules():
        routes.append({
            "endpoint": rule.endpoint,
            "methods": list(rule.methods),
            "rule": str(rule)
        })
    return jsonify({"routes": routes})

print("✅ Registered /debug_routes")

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "auto_sharing": True,
        "endpoints": [
            "/update_user_path_config",
            "/get_user_path_config",
            "/test_path_validation",
            "/debug_routes",
            "/health"
        ]
    })

print("✅ Registered /health")

# Your existing endpoints (keeping them as-is to avoid breaking other functionality)

@app.route("/send_email", methods=["POST"])
def send_email():
    """API endpoint to send an email message using SMTP"""
    data = request.json
    to = data.get("to")
    message = data.get("message")
    subject = data.get("subject", "WindTexter")
    delivery_path = data.get("delivery_path", "")

    # Map legacy/alias delivery paths to canonical names
    alias_map = {
        "send_email": "email",
        "send_sms": "sms"
    }
    delivery_path = alias_map.get(delivery_path, delivery_path)

    if not to or not message:
        return jsonify({"error": "Missing fields"}), 400

    if not validate_path(delivery_path):
        return jsonify({"error": f"Invalid path: {delivery_path}"}), 400

    try:
        msg = EmailMessage()
        msg.set_content(message)
        msg["Subject"] = subject
        msg["From"] = SMTP_EMAIL
        msg["To"] = to

        # Use SMTP_SSL for secure email sending
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
            smtp.login(SMTP_EMAIL, SMTP_PASSWORD)
            smtp.send_message(msg)

        return jsonify({"status": "sent"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

Twilio_SID = os.getenv("TWILIO_SID")
Twilio_AUTH = os.getenv("TWILIO_AUTH")
Twilio_FROM = os.getenv("TWILIO_FROM")

@app.route("/send_sms", methods=["POST"])
def send_sms():
    data = request.json
    to = data.get("to")
    message = data.get("message")
    sender_id = data.get("sender_id")
    real_text = data.get("real_text")
    bitstream = data.get("bitstream", [])
    bit_count = data.get("bit_count", 0)
    message_id = data.get("id") or str(uuid.uuid4())

    if not to or not message:
        return jsonify({"error": "Missing fields"}), 400

    try:
        client = Client(TWILIO_SID, TWILIO_AUTH)
        msg = client.messages.create(
            body=message,
            from_=TWILIO_FROM,
            to=to
        )

        stored_data = {
            "id": message_id,
            "real_text": real_text,
            "cover_text": message,
            "bitstream": bitstream,
            "bit_count": bit_count,
            "delivery_path": "sms",
            "sender_id": sender_id,
            "is_sent_by_current_user": True
        }

        from flask import json
        with app.test_request_context():
            with app.test_client() as client:
                client.post('/store_message', json=stored_data)

        return jsonify({"status": "sent", "sid": msg.sid})

    except Exception as e:
        return jsonify({"error": str(e)}), 500

# Load tokenizer and model
model_name = "distilgpt2"
tokenizer = GPT2Tokenizer.from_pretrained(model_name)
model = GPT2LMHeadModel.from_pretrained(model_name)
model.eval()

CHUNK_SIZE = 4
TOP_K = 2 ** CHUNK_SIZE

STORAGE_PATH = "api_storage"
os.makedirs(STORAGE_PATH, exist_ok=True)

def text_to_bits(text: str, method: str = DEFAULT_COMPRESSION_METHOD) -> list[int]:
    compressor = Compressor(method=method)
    compressed_bits = compressor.compress(text)

    print(f"[DEBUG] Compressed bits ({len(compressed_bits)} bits): {compressed_bits[:64]}...")

    iv_arg = DEFAULT_IV if DEFAULT_ENCRYPTION_MODE == 'OFB' else None

    encryptor = Encryptor(
        mode=DEFAULT_ENCRYPTION_MODE,
        key=DEFAULT_KEY,
        key_length=DEFAULT_KEY_LENGTH,
        iv=iv_arg
    )

    encrypted_bits = encryptor.encrypt(compressed_bits)

    print(f"[DEBUG] Encrypted bits ({len(encrypted_bits)} bits): {encrypted_bits[:64]}...")

    return encrypted_bits

def bits_to_text(bits: list[int], method: str = DEFAULT_COMPRESSION_METHOD) -> str:
    print("[DEBUG] bits_to_text(): Starting")
    
    if method == "default":
        method = 'utf8'

    encryptor = Encryptor(
        mode=DEFAULT_ENCRYPTION_MODE,
        key=DEFAULT_KEY,
        key_length=DEFAULT_KEY_LENGTH,
        iv=None
    )

    try:
        print("[DEBUG] Decrypting...")
        decrypted_bits = encryptor.decrypt(bits)
        print(f"[DEBUG] Decrypted {len(decrypted_bits)} bits")
    except Exception as e:
        print(f"[ERROR] Decryption failed: {e}")
        raise

    try:
        print(f"[DEBUG] Decompressing using method: {method}")
        compressor = Compressor(method=method)
        text = compressor.decompress(decrypted_bits)
        print("[DEBUG] Decompression successful")
        return text
    except Exception as e:
        print(f"[ERROR] Decompression failed: {e}")
        raise

def encode_message_to_cover_text(bit_sequence):
    import random
    style_prompts = [
        "Say something casual like you're texting a friend. Keep it under 2 sentences.",
        "Write a short, vague message someone might send in chat. Keep it brief.",
        "Text something natural and ambiguous in under 20 words.",
        "Casual chat message. Two sentences max. Sounds normal.",
        "Make it sound like a quick message to a friend. Nothing specific."
    ]
    seed_prompt = random.choice(style_prompts)
    input_ids = tokenizer.encode(seed_prompt, return_tensors="pt")
    generated_tokens = []
    used_chunks = 0

    while len(bit_sequence) % CHUNK_SIZE != 0:
        bit_sequence.append(0)
    bit_chunks = [bit_sequence[i:i + CHUNK_SIZE] for i in range(0, len(bit_sequence), CHUNK_SIZE)]

    for chunk in bit_chunks:
        target_index = int(''.join(map(str, chunk)), 2)
        with torch.no_grad():
            outputs = model(input_ids=input_ids)
        logits = outputs.logits[:, -1, :].squeeze()
        sorted_indices = torch.topk(logits, TOP_K).indices.tolist()
        token_id = sorted_indices[target_index % len(sorted_indices)]
        token_str = tokenizer.decode([token_id], skip_special_tokens=True, clean_up_tokenization_spaces=True)
        token_str = ''.join(char for char in token_str if char.isprintable() and ord(char) < 128)
        generated_tokens.append(token_str)
        used_chunks += 1
        next_token_tensor = torch.tensor([[token_id]], dtype=torch.long)
        input_ids = torch.cat([input_ids, next_token_tensor], dim=1)
        joined = "".join(generated_tokens).strip()
        if joined.count(".") + joined.count("!") + joined.count("?") >= 2 or len(joined.split()) > 20:
            break
    return "".join(generated_tokens).strip(), used_chunks * CHUNK_SIZE

@app.route('/decode_cover_chunks', methods=['POST'])
def decode_cover_chunks():
    data = request.json
    bit_sequence = data.get("bit_sequence", [])
    method = data.get("compression_method", DEFAULT_COMPRESSION_METHOD)

    bit_sequence = [int(b) for b in bit_sequence]

    if not bit_sequence:
        print("[ERROR] Received empty bit_sequence")
        return jsonify({"error": "Empty bit_sequence"}), 400

    if not isinstance(bit_sequence, list) or not all(bit in [0, 1] for bit in bit_sequence):
        return jsonify({"error": "Invalid bit_sequence"}), 400

    try:
        print(f"[DEBUG] Received bit_sequence (len={len(bit_sequence)}): {bit_sequence[:32]}")
        print(f"[DEBUG] Compression method: {method}")

        print("[DEBUG] Calling bits_to_text...")
        decoded_text = bits_to_text(bit_sequence, method)
        print("[DEBUG] Decoding successful.")

        return jsonify({"decoded_text": decoded_text})
    except Exception as e:
        print(f"[ERROR] decode_cover_chunks failed: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route("/split_cover_chunks", methods=["POST"])
def split_cover_chunks():
    data = request.json
    message = data.get("message", "")
    path = data.get("path", "WindTexter")

    print(f"[DEBUG] Message received: {message}")
    print(f"[DEBUG] Path received: {path}")

    try:
        bitstream = text_to_bits(message)
        return jsonify({
            "bitstream": [str(b) for b in bitstream],
            "bit_count": len(bitstream)
        })
    except Exception as e:
        print(f"[ERROR] Exception in split_cover_chunks: {e}")
        return "Internal Server Error", 500

@app.route('/fetch_conversation_messages', methods=['POST'])
def fetch_conversation_messages():
    """Fetch messages for a specific conversation between two users"""
    try:
        data = request.json
        delivery_path = data.get("delivery_path", "email")
        current_user_email = data.get("current_user_email", "").lower()
        chat_partner_email = data.get("chat_partner_email", "").lower()
        device_id = data.get("device_id", "")
        chat_id = data.get("chat_id", "")
        
        print(f"🔍 Fetching conversation messages:")
        print(f"   delivery_path: {delivery_path}")
        print(f"   current_user: {current_user_email}")
        print(f"   partner: {chat_partner_email}")
        print(f"   device_id: {device_id}")
        print(f"   chat_id: {chat_id}")
        
        path_file = os.path.join(STORAGE_PATH, f"{delivery_path}_db.json")

        if not os.path.exists(path_file):
            print(f"📂 No messages file found: {path_file}")
            return jsonify({"messages": []})

        with open(path_file, 'r') as f:
            try:
                all_messages = json.load(f)
            except json.JSONDecodeError:
                all_messages = []

        print(f"📂 Loaded {len(all_messages)} total messages from {path_file}")

        # Filter messages for this specific conversation
        conversation_messages = []
        
        for message in all_messages:
            # Check if message belongs to this conversation
            sender_email = message.get("sender_email", "").lower()
            recipient_email = message.get("recipient_email", "").lower()
            msg_sender_id = message.get("sender_id", "")
            
            # Check if this message is part of the conversation between current_user and chat_partner
            is_current_to_partner = (
                sender_email == current_user_email and
                recipient_email == chat_partner_email
            ) or (msg_sender_id == device_id and recipient_email == chat_partner_email)
            
            is_partner_to_current = (
                sender_email == chat_partner_email and
                recipient_email == current_user_email
            ) or (recipient_email == current_user_email and sender_email == chat_partner_email)
            
            if is_current_to_partner or is_partner_to_current:
                conversation_messages.append(message)
        
        print(f"📧 Found {len(conversation_messages)} messages for conversation")
        
        # Add ownership information
        for message in conversation_messages:
            msg_sender_id = message.get("sender_id", "")
            message["is_sent_by_current_user"] = (msg_sender_id == device_id)
            
            # Ensure proper field names for iOS compatibility
            if "real_text" in message:
                message["realText"] = message["real_text"]
            if "cover_text" in message:
                message["coverText"] = message["cover_text"]
            if "image_data" in message and message["image_data"]:
                message["imageData"] = message["image_data"]

        return jsonify({"messages": conversation_messages})
        
    except Exception as e:
        print(f"❌ Error in fetch_conversation_messages: {e}")
        return jsonify({"error": str(e), "messages": []}), 500

@app.route('/fetch_messages', methods=['POST'])
def fetch_messages():
    try:
        data = request.json
        path = data.get("delivery_path", "generic")
        device_id = data.get("device_id")
        
        path_file = os.path.join(STORAGE_PATH, f"{path}_db.json")

        if not os.path.exists(path_file):
            return jsonify({"messages": []})

        with open(path_file, 'r') as f:
            try:
                all_messages = json.load(f)
            except json.JSONDecodeError:
                all_messages = []

        from datetime import datetime, timezone, timedelta
        cutoff = datetime.now(timezone.utc) - timedelta(minutes=10)
        seen_ids = set(data.get("seen_message_ids", []))
        recent_messages = []

        for message in all_messages:
            try:
                timestamp_str = message.get("timestamp", "")
                if timestamp_str.endswith('Z'):
                    timestamp_str = timestamp_str[:-1] + '+00:00'
                elif not timestamp_str.endswith('+00:00'):
                    timestamp_str += '+00:00'

                msg_time = datetime.fromisoformat(timestamp_str)
                msg_id = message.get("id")

                if msg_time > cutoff and msg_id not in seen_ids:
                    recent_messages.append(message)
            except Exception as e:
                continue

        for message in recent_messages:
            msg_sender = message.get("sender_id")
            message["is_sent_by_current_user"] = (msg_sender == device_id)
            
            if "real_text" in message:
                message["realText"] = message["real_text"]
            if "cover_text" in message:
                message["coverText"] = message["cover_text"]
            if "image_data" in message and message["image_data"]:
                message["imageData"] = message["image_data"]
                print(f"📸 Including image data for message {msg_id}")

        return jsonify({"messages": recent_messages})
        
    except Exception as e:
        print(f"[ERROR] fetch_messages failed: {e}")
        return jsonify({"error": str(e), "messages": []}), 500

@app.route("/send_email_with_image", methods=["POST"])
def send_email_with_image():
    """API endpoint to send an email message with optional image attachment"""
    data = request.json
    to = data.get("to")
    message = data.get("message", "")
    subject = data.get("subject", "WindTexter")
    image_data = data.get("image_data")
    image_filename = data.get("image_filename", "image.jpg")

    print(f"📧 send_email_with_image called:")
    print(f"   to: {to}")
    print(f"   message: '{message}'")
    print(f"   has_image: {image_data is not None}")
    if image_data:
        print(f"   image_data length: {len(image_data)} chars")

    if not to:
        print("❌ Missing 'to' field")
        return jsonify({"error": "Missing 'to' field"}), 400
    
    if not message and not image_data:
        print("❌ Missing both message and image")
        return jsonify({"error": "Must provide either message or image"}), 400

    try:
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText
        from email.mime.base import MIMEBase
        from email import encoders
        import base64

        msg = MIMEMultipart()
        msg["Subject"] = subject
        msg["From"] = SMTP_EMAIL
        msg["To"] = to

        if message:
            msg.attach(MIMEText(message, "plain"))
        else:
            msg.attach(MIMEText("📸 Image message", "plain"))

        if image_data:
            try:
                print(f"🔧 Decoding base64 image data...")
                image_bytes = base64.b64decode(image_data)
                print(f"✅ Decoded {len(image_bytes)} bytes")
                
                part = MIMEBase("application", "octet-stream")
                part.set_payload(image_bytes)
                encoders.encode_base64(part)
                part.add_header(
                    "Content-Disposition",
                    f"attachment; filename= {image_filename}",
                )
                msg.attach(part)
                print(f"📎 Added image attachment: {image_filename} ({len(image_bytes)} bytes)")
            except Exception as e:
                print(f"❌ Failed to attach image: {e}")

        print(f"📤 Sending email...")
        with smtplib.SMTP_SSL("smtp.gmail.com", 465) as smtp:
            smtp.login(SMTP_EMAIL, SMTP_PASSWORD)
            smtp.send_message(msg)

        print(f"✅ Email sent successfully!")
        return jsonify({"status": "sent"})
    except Exception as e:
        print(f"❌ Email sending failed: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@app.route('/generate_reply', methods=['POST'])
def generate_reply():
    data = request.json
    history = data.get("chat_history", [])
    last_message = data.get("last_message", "").strip()
    if not last_message:
        return jsonify({"error": "No last_message provided"}), 400
    context = "\n".join(history[-5:])
    prompt = f"{context}\nUser: {last_message}\nFriend:"
    input_ids = tokenizer.encode(prompt, return_tensors="pt")
    with torch.no_grad():
        output = model.generate(
            input_ids,
            max_length=input_ids.shape[1] + 30,
            num_return_sequences=1,
            pad_token_id=tokenizer.eos_token_id,
            do_sample=True,
            top_k=50,
            top_p=0.95
        )
    reply = tokenizer.decode(output[0], skip_special_tokens=True)
    reply_text = reply[len(prompt):].strip().split("\n")[0]
    return jsonify({"reply": reply_text})

@app.route('/check_available_paths', methods=['POST'])
def check_available_paths():
    data = request.json
    phone = data.get("phone")
    email = data.get("email")
    region = data.get("region", "US")

    available = []

    region_defaults = {
        "US": ["SMS", "Email"],
        "EU": ["Email"],
        "IN": ["SMS"],
    }
    available.extend(region_defaults.get(region, ["Email"]))

    if not phone:
        available = [x for x in available if x != "SMS"]
    if not email:
        available = [x for x in available if x != "Email"]

    return jsonify({"availablePaths": sorted(list(set(available)))})

@app.route('/store_message', methods=['POST'])
def store_message():
    data = request.json

    print("📥 /store_message received:")
    real_text = data.get("real_text") or data.get("realText")
    cover_text = data.get("cover_text") or data.get("coverText")
    print("   realText:", real_text)
    print("   coverText:", cover_text)
    print("   imageData present:", "image_data" in data)
    
    if "image_data" in data and data["image_data"]:
        image_data_len = len(data.get("image_data", ""))
        print(f"   imageData size: {image_data_len} characters")
        
        try:
            import base64
            decoded = base64.b64decode(data["image_data"])
            print(f"   Decoded image size: {len(decoded)} bytes")
        except Exception as e:
            print(f"   ❌ Failed to decode image: {e}")

    alias_map = {
        "send_email": "email",
        "send_sms": "sms"
    }

    raw_path = data.get("delivery_path", "generic").lower()
    path = alias_map.get(raw_path, raw_path)

    if not validate_path(path):
        return jsonify({"error": f"Invalid path: {path}"}), 400

    path_file = os.path.join(STORAGE_PATH, f"{path}_db.json")

    is_sent_by_current_user = data.get("is_sent_by_current_user", False)

    complete_data = {
        "id": data.get("id"),
        "delivery_path": path,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "bitstream": data.get("bitstream", []),
        "is_sent_by_current_user": is_sent_by_current_user,
        "real_text": real_text or "",
        "cover_text": cover_text or "",
        "bit_count": data.get("bit_count") or data.get("bitCount", 0),
        "is_auto_reply": data.get("is_auto_reply") or data.get("isAutoReply", False),
        "image_data": data.get("image_data", None),
        "sender_id": data.get("sender_id", None),
        "sender_email": data.get("sender_email", None),
        "recipient_email": data.get("recipient_email", None),
    }
    
    print(f"📦 Final data being stored:")
    print(f"   real_text: '{complete_data['real_text']}'")
    print(f"   cover_text: '{complete_data['cover_text'][:50]}...'")
    print(f"   image_data present: {complete_data['image_data'] is not None}")

    if os.path.exists(path_file):
        with open(path_file, 'r') as f:
            try:
                db = json.load(f)
            except json.JSONDecodeError as e:
                db = []
    else:
        db = []

    db.append(complete_data)

    with open(path_file, 'w') as f:
        json.dump(db, f, indent=2)

    print("✅ Message stored successfully")
    return jsonify({"status": "stored", "message": complete_data})

# CRITICAL FIX: Add CORS headers for better compatibility
@app.after_request
def after_request(response):
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
    return response

# Final debug output
print("🎯 Route registration complete!")

if __name__ == '__main__':
    print("\n🚀 Starting WindTexter server...")
    print("Available endpoints:")
    print("  POST /update_user_path_config (auto-sharing enabled)")
    print("  POST /get_user_path_config (auto-sharing enabled)")
    print("  POST /test_path_validation")
    print("  GET /debug_routes")
    print("  GET /health")
    print("\n🔧 Simplified version:")
    print("  - All enabled paths are automatically shared")
    print("  - No manual path sharing toggle needed")
    print("  - Users' enabled paths are always visible to contacts")
    print("\n" + "="*50)
    app.run(host='0.0.0.0', port=4000, debug=True)
