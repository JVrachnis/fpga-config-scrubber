from projectTools.arrayTools import split_array_by_length

def find_non_essential_frames(essential,frame_bit_size):
    frames = split_array_by_length(essential,frame_bit_size)
    frames_non_essential=[True]*len(frames)
    for frame_index, frame in enumerate(frames):# one liner [frame_index for frame_index, frame in enumerate(frames) if not ('0' in frame)]
        frames_non_essential[frame_index]=not('1' in frame)
    return frames_non_essential

def find_binary_non_essential_frames(essential,frame_byte_size):
    frames = split_array_by_length(essential,frame_byte_size)
    frames_non_essential=[True]*len(frames)
    essential_byte=0
    for frame_index, frame in enumerate(frames):# one liner [frame_index for frame_index, frame in enumerate(frames) if not ('0' in frame)]
        is_non_essential=True
        for byte in frame:
            if byte != essential_byte :
                is_non_essential=False
                break
        frames_non_essential[frame_index]=is_non_essential
    return frames_non_essential
