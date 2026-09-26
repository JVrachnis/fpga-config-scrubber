import numpy as np
import matplotlib.pyplot as plt

x,y=np.loadtxt("test1_plot_data.csv", delimiter=",", unpack=True)


plt.hist2d(x, y, bins=[int(10009), int(3232)], cmap='Reds')
cb = plt.colorbar()
cb.set_label('counts in bin')

plt.show()
