#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
This file includes the compression algorithm LZ77 algorithm 

@author: massieh
"""

from bitarray import bitarray

class LZ77Compressor:
	"""
	A simplified implementation of the LZ77 Compression Algorithm
    
    This algorithm looks for repeated pattern in a window related to the current 
    position. The slidng window starts from current_position - window_size to
    current_position + lookahead_buffer_size. The patterns that are found have 
    at most lookahead_buffer_size size. 
    
    !!! I don't know why 12 bits are allocated for distance as the maximum window
    size is 400 therefore 9 bits should be enough.' 
        
	"""
	MAX_WINDOW_SIZE = 400

	def __init__(self, window_size=20):
		self.window_size = min(window_size, self.MAX_WINDOW_SIZE) 
		self.lookahead_buffer_size = 15 # length of match is at most 4 bits

	def compress_data(self, data: str, verbose= False) -> bitarray:
		"""
		Given the input string, it is compressed by applying a simple 
		LZ77 compression algorithm. 
		The compressed format is:
		0 bit followed by 8 bits (1 byte character) when there are no previous matches
			within window
		1 bit followed by 12 bits pointer (distance to the start of the match from the 
			current position) and 4 bits (length of the match)
		
		The compressed text is returned as a bitarray
		if verbose is enabled, the compression description is printed to standard output
        
		"""
		data = data.encode('utf-8')
		i = 0
		output_buffer = bitarray(endian='big')

	
		while i < len(data):

			match = self.findLongestMatch(data, i)

			if match: 
				# Add 1 bit flag, followed by 12 bit for distance, and 4 bit for the length
				# of the match 
				(bestMatchDistance, bestMatchLength) = match

				output_buffer.append(True)
                # This line adds the multiples of 16 in bestMatchDistance in binarry to the output_buffer
				output_buffer.frombytes(bytes([bestMatchDistance >> 4])) 
                # This line adds the remainder of bestMatchDistance in binary and 
                # then shifts it 4 times and then adds the bestMatchLength
				output_buffer.frombytes(bytes([((bestMatchDistance & 0xf) << 4) | bestMatchLength])) 
               
				if verbose:
					print("<1, %i, %i>" % (bestMatchDistance, bestMatchLength), end='')

				i += bestMatchLength

			else:
				# No useful match was found. Add 0 bit flag, followed by 8 bit for the character
				output_buffer.append(False)
				output_buffer.frombytes(bytes([data[i]]))
				
				if verbose:
					print("<0, %s>" % data[i], end='')

				i += 1

		# fill the buffer with zeros if the number of bits is not a multiple of 8		
		output_buffer.fill()

		return output_buffer


	def decompress(self, data):
		"""
        Decompresses binary data back to its original string.

        Parameters:
        data (bitarray): Compressed binary data.

        Returns:
        str: Decompressed string.
        """
		
		output_buffer = []
		data = data.copy()

		while len(data) >= 9:

			flag = data.pop(0)

			if not flag:
				byte = data[0:8].tobytes()

				output_buffer.append(byte)
				del data[0:8]
			else:
				byte1 = ord(data[0:8].tobytes())
				byte2 = ord(data[8:16].tobytes())

				del data[0:16]
				distance = (byte1 << 4) | (byte2 >> 4)
				length = (byte2 & 0xf)

				for _ in range(length):
					output_buffer.append(output_buffer[-distance])
		out_data =  b''.join(output_buffer).decode('utf-8')

		return out_data


	def findLongestMatch(self, data, current_position):
		"""
        Finds the longest match for LZ77 compression.

        Parameters:
        data (bytes): The input data.
        current_position (int): Current position in the data.

        Returns:
        tuple: (distance, length) of the match, or None if no match is found.
        """
		end_of_buffer = min(
			current_position + self.lookahead_buffer_size, len(data) + 1
		)

		best_match_distance = -1
		best_match_length = -1

		# Optimization: Only consider substrings of length 2 and greater, and just 
		# output any substring of length 1 (8 bits uncompressed is better than 13 bits
		# for the flag, distance, and length)
        
        # This loop is for the string pattern from current position onwards. This 
        # is the pattern we try to find in the past history
		for j in range(current_position + 2, end_of_buffer):

			start_index = max(0, current_position - self.window_size)
			substring = data[current_position:j]

			for i in range(start_index, current_position):
                
                # The repetitions and last are for referring to a length greater
                # than the distance, for example, for saying ditance=5, and length=12

				repetitions = len(substring) // (current_position - i)

				last = len(substring) % (current_position - i)

				matched_string = (
					data[i:current_position] * repetitions + data[i:i+last]
				)

				if matched_string == substring and len(substring) > best_match_length:
					best_match_distance = current_position - i 
					best_match_length = len(substring)

		if best_match_distance > 0 and best_match_length > 0:
			return best_match_distance, best_match_length
		return None

