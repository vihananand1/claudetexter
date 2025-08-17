from heapq import heappush, heappop
from collections import defaultdict, Counter
from bitarray import bitarray

class HuffmanCompressor:
    def build_tree(self, text):
        freq = Counter(text)
        for char in text:
            freq[char] += 1

        heap = [[weight, [char, ""]] for char, weight in freq.items()]
        while len(heap) > 1:
            low = heappop(heap)
            high = heappop(heap)
            for pair in low[1:]:
                pair[1] = '0' + pair[1]
            for pair in high[1:]:
                pair[1] = '1' + pair[1]
            heappush(heap, [low[0] + high[0]] + low[1:] + high[1:])

            # Convert values to bitarray
        tree = dict(heappop(heap)[1:])
        for char, code in tree.items():
            tree[char] = bitarray(code)  # Convert each binary string to bitarray
        return tree

    def compress(self, text):
        tree = self.build_tree(text)
        compressed = bitarray()
        compressed.encode(tree, text)  # Directly encode the text using the tree
        return compressed

    def decompress(self, compressed, tree):
        reverse_tree = {v.to01(): k for k, v in tree.items()}
        decoded = []
        buffer = ""
        for bit in compressed.to01():
            buffer += bit
            if buffer in reverse_tree:
                decoded.append(reverse_tree[buffer])
                buffer = ""
        return "".join(decoded)

# Example Usage
if __name__ == "__main__":
    compressor = HuffmanCompressor()
    text = "aaaaabbc"
    tree = compressor.build_tree(text)
    compressed = compressor.compress(text)
    print(f"Compressed: {compressed}")
    print(f"Tree: {tree}")
    decompressed = compressor.decompress(compressed, tree)
    print(f"Decompressed: {decompressed}")
