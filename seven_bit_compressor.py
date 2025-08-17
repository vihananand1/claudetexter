from bitarray import bitarray

class SevenBitCompressor:
    # Define the character set and mappings
    CHARSET = (
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        "abcdefghijklmnopqrstuvwxyz"
        "0123456789 .,?!-_():;'\"@#$%^&*+=~©®\n"
    )
    ENCODE_MAP = {char: idx for idx, char in enumerate(CHARSET)}
    DECODE_MAP = {idx: char for idx, char in enumerate(CHARSET)}

    def compress(self, text: str) -> bitarray:
        """
        Compress the given text using 7-bit encoding.

        Parameters:
        text (str): The text to compress.

        Returns:
        bitarray: The compressed binary data.
        """
        ba = bitarray(endian="big")
        for char in text:
            if char not in self.ENCODE_MAP:
                raise ValueError(f"Unsupported character: {char}")
            # Convert the character to its 7-bit binary representation
            ba.extend(format(self.ENCODE_MAP[char], "07b"))
        return ba

    def decompress(self, compressed: bitarray) -> str:
        """
        Decompress the given binary data back to text using 7-bit encoding.

        Parameters:
        compressed (bitarray): The compressed binary data.

        Returns:
        str: The decompressed text.
        """
        text = []
        for i in range(0, len(compressed), 7):
            # Extract 7 bits at a time and convert to integer
            char_code = int(compressed[i:i + 7].to01(), 2)
            if char_code not in self.DECODE_MAP:
                raise ValueError(f"Invalid character code: {char_code}")
            text.append(self.DECODE_MAP[char_code])
        return "".join(text)
