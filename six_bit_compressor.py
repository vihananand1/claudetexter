from bitarray import bitarray

class SixBitCompressor:
    # Define the character set and mappings
    CHARSET = (
        "abcdefghijklmnopqrstuvwxyz"
        "0123456789 .,?!-_:;'\"()[]{}@#$%^&*~\n"
    )
    ENCODE_MAP = {char: idx for idx, char in enumerate(CHARSET)}
    DECODE_MAP = {idx: char for idx, char in enumerate(CHARSET)}

    def compress(self, text: str) -> bitarray:
        """
        Compress the given text using 6-bit encoding. Converts uppercase to lowercase.

        Parameters:
        text (str): The text to compress.

        Returns:
        bitarray: The compressed binary data.
        """
        ba = bitarray(endian="big")
        for char in text:
            lower_char = char.lower()
            if lower_char not in self.ENCODE_MAP:
                raise ValueError(f"Unsupported character: {char}")
            # Convert the character to its 6-bit binary representation
            ba.extend(format(self.ENCODE_MAP[lower_char], "06b"))
        return ba

    def decompress(self, compressed: bitarray) -> str:
        """
        Decompress the given binary data back to text using 6-bit encoding.

        Parameters:
        compressed (bitarray): The compressed binary data.

        Returns:
        str: The decompressed text (in lowercase).
        """
        text = []
        for i in range(0, len(compressed), 6):
            # Extract 6 bits at a time and convert to integer
            char_code = int(compressed[i:i + 6].to01(), 2)
            if char_code not in self.DECODE_MAP:
                raise ValueError(f"Invalid character code: {char_code}")
            text.append(self.DECODE_MAP[char_code])
        return "".join(text)
