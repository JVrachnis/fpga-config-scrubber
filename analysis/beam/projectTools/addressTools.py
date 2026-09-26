def frames_to_addresses(frame_indexs,addresses):
    masked_addresses =[]
    for frame_index in frame_indexs:# one liner [address_list[frame_index] for frame_index in frame_indexs]
        masked_address = addresses[frame_index]
        masked_addresses.append(masked_address)
    return masked_addresses
