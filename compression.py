from .LZ77 import LZ77Compressor
from .huffman import HuffmanCompressor
from .six_bit_compressor import SixBitCompressor
from .seven_bit_compressor import SevenBitCompressor
from bitarray import bitarray

class Compressor:
        # Compression Block: Convert secret plaintext to message bits, there are two
        # methods of compression in here, either UTF8 (no compression) or LZ77.
        # The input to the compression block is a plain text (plaintext) and the
        # output is a bitarray (message)
        VALID_METHODS = {'utf8', 'lz77', 'huffman', 'six_bit', 'seven_bit'}
        def __init__(self, method = 'utf8'):
            """
            Initializes the Compressor with the specified compression method.

            Parameters:
            method (str): The compression method to be used (e.g., 'utf8', 'lz77').
            """
            self.method = method.lower()
            if self.method not in self.VALID_METHODS:
                raise ValueError(f"Unsupported compression method: {self.method}")

        def compress(self, plaintext: str) -> bitarray:
            """
            Compresses the given plaintext using the specified method.

            Parameters:
            plaintext (str): The text to compress.

            Returns:
            bitarray: Compressed binary data.
            """
            if not isinstance(plaintext, str):
                raise TypeError("Input plaintext must be a string.")
            if self.method == 'utf8':
                return self._utf8_compress(plaintext)
            elif self.method == 'lz77':
                compressor = LZ77Compressor()
                return compressor.compress_data(plaintext)
            elif self.method == 'huffman':
                compressor = HuffmanCompressor()
                return compressor.compress(plaintext)
            elif self.method == 'six_bit':
                return SixBitCompressor().compress(plaintext)
            elif self.method == 'seven_bit':
                return SevenBitCompressor().compress(plaintext)
            else:
                raise ValueError(f"Unsupported compression method: {self.method}")

        def decompress(self, compressed: bitarray) -> str:
            """
            Decompresses the given binary data using the specified method.

            Parameters:
            compressed (bitarray): Compressed binary data.

            Returns:
            str: Decompressed text.
            """
            if not isinstance(compressed, bitarray):
                raise TypeError("Input compressed data must be a bitarray.")
            if self.method == 'utf8':
                return compressed.tobytes().decode('utf-8')
            elif self.method == 'lz77':
                compressor = LZ77Compressor()
                return compressor.decompress(compressed)
            elif self.method == 'huffman':
                return HuffmanCompressor().decompress(compressed)
            elif self.method == 'six_bit':
                return SixBitCompressor().decompress(compressed)
            elif self.method == 'seven_bit':
                return SevenBitCompressor().decompress(compressed)
            else:
                raise ValueError(f"Unsupported compression method: {self.method}")
        
        def _utf8_compress(self, plaintext: str) -> bitarray:
            """
            Converts the given plaintext to a bitarray using UTF-8 encoding.

            Parameters:
            plaintext (str): The plaintext to be converted.

            Returns:
            bitarray: The bitarray representation of the plaintext.
            """

           
            ba = bitarray(endian="big")
            ba.frombytes(plaintext.encode("utf-8"))
            #message = ba.tolist()
            return ba
