import numpy as np
import random
import operator
import time
def patern_finder(error_board,patern_location,patern_list,depth,max_depth):
    while np.size(error_board,1)>0 and not(np.any(error_board[:, 0] == 1)):
        patern_location[1,0]+=1
        error_board = error_board[:,1:]
    while np.size(error_board,1)>0 and not(np.any(error_board[:, -1] == 1)):
        patern_location[1,1]-=1
        error_board = error_board[:,:-1]
    while np.size(error_board,0)>0 and not(np.any(error_board[0] == 1)):
        patern_location[0,0]+=1
        error_board = error_board[1:]
    while np.size(error_board,0)>0 and not(np.any(error_board[-1] == 1)):
        patern_location[0,1]-=1
        error_board = error_board[:-1]

    #print(error_board)

    #if depth >=max_depth:
    #    return patern_list
    patern=str(error_board.tolist())
    tmp_locetion=str(patern_location.tolist())
    if(np.size(error_board,0)>0):
        if patern in patern_list:

            if tmp_locetion in patern_list[patern][1]:
                return patern_list
            patern_list[patern][0]+=1
            patern_list[patern][1].append(tmp_locetion)

        else:
            patern_list[patern]=[1,[tmp_locetion]]



    if(np.size(error_board,0)>1):
        tmp_patern_location=np.copy(patern_location)
        tmp_patern_location[0,0]+=1
        patern_list=patern_finder(error_board[1:],tmp_patern_location,patern_list,depth+1,max_depth)

        tmp_patern_location= np.copy(patern_location)
        tmp_patern_location[0,1]-=1
        patern_list=patern_finder(error_board[:-1],tmp_patern_location,patern_list,depth+1,max_depth)

    if(np.size(error_board,1)>1):
        tmp_patern_location=np.copy(patern_location)
        tmp_patern_location[1,0]+=1
        patern_list=patern_finder(error_board[:,1:],tmp_patern_location,patern_list,depth+1,max_depth)

        tmp_patern_location=np.copy(patern_location)
        tmp_patern_location[1,1]-=1
        patern_list=patern_finder(error_board[:,:-1],tmp_patern_location,patern_list,depth+1,max_depth)

    return patern_list

size=int((10009*101*32)**(1/2))
size=128
print(size)
error_board= np.zeros((size,size),dtype=np.int)
max_errors=90
for i in range(0,max_errors):
    x=random.randint(0,64-1)
    y=random.randint(0,64-1)
    error_board[x,y]=1
#error_board=np.array([[0,1],[1,0]])
print(error_board)
errors = (error_board==1).sum()
print(errors)
error_spreding_score=0
error_possistions=zip(np.where(error_board==1)[0],np.where(error_board==1)[1])
for error_possistion in error_possistions:
    for error_possistion1 in error_possistions:
        error_spreding_score+= ((error_possistion[0]-error_possistion1[0])**2 +(error_possistion[1]-error_possistion1[1])**2)#**(1/2)
error_spreding_score = error_spreding_score
print(error_spreding_score)
start_time = time.time()
patern_list = patern_finder(error_board,np.array([[0,size],[0,size]]),{},0,1)
end_time = time.time()-start_time

patern_cont_list={}
#print(patern_list)
for patern in patern_list.keys():
    patern_cont_list[patern]=patern_list[patern][0]

sorted_x = sorted(patern_cont_list.items(), key=operator.itemgetter(1))
print(len(sorted_x))
print(sorted_x[-7:])
print(error_spreding_score,error_spreding_score/end_time,end_time)
#if(sorted_x[-2][1]>1):
#    print(sorted_x[-2])
