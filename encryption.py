from Crypto.Cipher import AES
from typing import List
from bitarray import bitarray

def bytes2bits(data: bytes) -> List[int]:
    """
    Converts a byte sequence into a list of bits.

    Parameters:
    data (bytes): The byte sequence to convert.

    Returns:
    List[int]: A list of bits representing the byte sequence.
    """
    return [int(bit) for byte in data for bit in f"{byte:08b}"]

def bits2bytes(bits: List[int]) -> bytes:
    """
    Converts a list of bits to bytes.

    Parameters:
    bits (list): The list of bits to convert.

    Returns:
    bytes: The byte representation of the bits.
    """
    byte_array = bytearray()
    for i in range(0, len(bits), 8):
        byte_chunk = bits[i:i+8]
        byte_value = sum(b << (7 - j) for j, b in enumerate(byte_chunk))
        byte_array.append(byte_value)
    return bytes(byte_array)

class Encryptor:
    def __init__(self, mode: str, key: bytes, key_length: int, iv: bytes = None) -> None:
        """
        Initializes the Encryptor with the specified mode, key, IV, and option to send nonce and tag.

        Parameters:
        mode (str): The encryption mode (e.g., 'EAX', 'OFB').
        key (bytes): The encryption key.
        key_length (int): The length of the encryption key in bits.
        iv (bytes, optional): The initialization vector for modes that require it (e.g., 'OFB').
        """
        self.mode = mode
        self.key = key
        self.iv = iv
        self.key_length = key_length
        

    def encrypt(self, message: bitarray) -> List[int]:
        """
        Encrypts the given message using the specified encryption mode.

        Parameters:
        message (bitarray): The message to be encrypted.

        Returns:
        List[int]: The encrypted message represented as a list of bits.
        """
        message_bytes = message.tobytes()

        if self.mode == 'EAX':
            cipher = AES.new(self.key, AES.MODE_EAX)
            ciphertext, tag = cipher.encrypt_and_digest(message_bytes)
            nonce = cipher.nonce
            cipher_bits = bytes2bits(nonce) + bytes2bits(tag) + bytes2bits(ciphertext)

        elif self.mode == 'OFB':
            if self.iv is None:
                raise ValueError("IV is required for OFB mode.")
            cipher = AES.new(self.key, AES.MODE_OFB, self.iv)
            ciphertext = cipher.encrypt(message_bytes)
            cipher_bits = bytes2bits(self.iv) + bytes2bits(ciphertext)
        else:
            raise ValueError(f"Unsupported encryption mode: {self.mode}")

        return cipher_bits

    def decrypt(self, ciphermessage: List[int]) -> bitarray:
        """
        Decrypts the given ciphermessage using the specified encryption mode.

        Parameters:
        ciphermessage (List[int]): The encrypted message represented as a list of bits.

        Returns:
        bitarray: The original plaintext message as a bitarray.
        """
        cipher_bytes = bits2bytes(ciphermessage)

        if self.mode == 'EAX':
            nonce = cipher_bytes[:16]
            tag = cipher_bytes[16:32]
            ciphertext = cipher_bytes[32:]
            cipher = AES.new(self.key, AES.MODE_EAX, nonce=nonce)
            plaintext_bytes = cipher.decrypt_and_verify(ciphertext, tag)

        elif self.mode == 'OFB':
            iv = cipher_bytes[:16]
            ciphertext = cipher_bytes[16:]
            cipher = AES.new(self.key, AES.MODE_OFB, iv)
            plaintext_bytes = cipher.decrypt(ciphertext)
        else:
            raise ValueError(f"Unsupported decryption mode: {self.mode}")

        result = bitarray()
        result.frombytes(plaintext_bytes)  
        return result

    