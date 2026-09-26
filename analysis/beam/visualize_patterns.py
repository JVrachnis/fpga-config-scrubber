import re
import ast
import os
import shutil

from os import listdir
from os.path import isfile, join
from PIL import Image, ImageDraw, ImageFont



def create_image(points, freq, folder):
	max_x = -1
	max_y = -1
	for i in points:
		if i[0] > max_x:
			max_x = i[0]
		if i[1] > max_y:
			max_y = i[1]
	im = Image.new('RGB', (max_x+1,max_y+1), "white")

	# Draw pattern with golden bit color
	for i in points:
		c = (255,0,0) # 0 : red
		if i[2] == 1: c = (0,0,255) # 1 : blue
		im.putpixel((i[0], i[1]), c)

	# Scale image
	resize_v = 10
	im = im.resize(((max_x+1)*resize_v,(max_y+1)*resize_v), Image.BOX)
	im = im.resize((im.size[0] + 2,im.size[1] + 2))

	draw = ImageDraw.Draw(im)

	# Add grid
	for x in range(0, im.size[0], resize_v):
		draw.line([(x, 0), (x, im.size[1])], fill='black', width=2)

	for y in range(0, im.size[1], resize_v):
		draw.line([(0, y), (im.size[0], y)], fill='black', width=2)

	# Add Masked border
	for i in points:
		x = i[0] * resize_v
		y = i[1] * resize_v
		if i[3] == 1:
			draw.rectangle([(x+2, y+2), (x+resize_v-1,y+resize_v-1)], outline='green')

	# Save Image without overwrite
	num = 0
	save_file = folder+'/'+str(freq)+'.png'
	while(isfile(save_file)):
		save_file = folder+"/"+str(freq)+'_'+str(num)+'.png'
		num+=1

	im.save(save_file, "PNG")

def clear_images_folder(folder):
	if os.path.isdir(folder):
		for f in listdir(folder):
			if(f != 'csv_files'):
				shutil.rmtree(folder+'/'+f)

# Setup folders
root_folder = 'patterns_images_threshold4/'
# test_folders = ['test1/', 'test2/', 'test3/']
test_folders = ['test1/']
csv_regex = 'test._app_paterns_*'


for test_folder in test_folders:

	# Delete old images
	clear_images_folder(root_folder + test_folder)

	csv_folder = root_folder + test_folder + 'csv_files/'
	files = [f for f in listdir(csv_folder)
		if isfile(join(csv_folder,f)) and re.match(csv_regex, f)]


	for file in files:

		filesplit = file.split('.')
		block_type = filesplit[2].split('=')[1]

		if re.match('masked_bit=*',filesplit[3]):
			masked = '_Masked' if filesplit[3].split('=')[1] == '1' else '_Unmasked'
		else:
			masked = ''

		readback_folder = 'readback_capture/' if filesplit[1].split('=')[1] == 'True' else 'readback/'
		angle_folder = 'angle/' if (re.match('is_angled=*', filesplit[-2]) and
									filesplit[-2].split('=')[1] == 'True') else 'not_Angle'

		block_folder = block_type + masked + '/'

		folder = root_folder + test_folder + readback_folder + block_folder + angle_folder
		if not os.path.exists(folder):
			os.makedirs(folder)

		with open(csv_folder+file) as file:
			data = file.read().splitlines()
			for i in data:
				l = ast.literal_eval(i)
				freq = l[0]
				points = [ast.literal_eval(k)[:2] for k in list(l[1:])]
				print(points[0])
