import numpy as np
import matplotlib.pyplot as plt


x,y=np.loadtxt("test2_plot_data.csv", delimiter=",", unpack=True)
plt.scatter(x, y)
plt.show()
