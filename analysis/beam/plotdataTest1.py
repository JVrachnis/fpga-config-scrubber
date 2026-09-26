import numpy as np
import matplotlib.pyplot as plt


x,y=np.loadtxt("test1_plot_data.csv", delimiter=",", unpack=True)
plt.scatter(x, y)
plt.show()
