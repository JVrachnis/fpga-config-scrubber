from projectTools.arrayTools import split_array_by_length
def find_masked_frames(mask,frame_bit_size):
    frames = split_array_by_length(mask,frame_bit_size)
    frames_masked=[False]*len(frames)
    for frame_index, frame in enumerate(frames):# one liner [frame_index for frame_index, frame in enumerate(frames) if not ('0' in frame)]
        frames_masked[frame_index]=not ('0' in frame)
    return frames_masked

def find_binary_masked_frames(mask,frame_byte_size):
    frames = split_array_by_length(mask,frame_byte_size)
    frames_masked=[False]*len(frames)
    masked_byte=255
    for frame_index, frame in enumerate(frames):# one liner [frame_index for frame_index, frame in enumerate(frames) if not ('0' in frame)]
        is_masked=True
        for byte in frame:
            if byte != masked_byte :
                is_masked=False
                break

        frames_masked[frame_index]=is_masked
    return frames_masked
