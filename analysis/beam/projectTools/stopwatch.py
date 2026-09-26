import time

class Stopwatch(object):
    """docstring for stopwatch."""
    __started=False
    __stoped=False
    __start_time=0
    __elapsed=0
    def Start(self):
        self.__start_time = time.time()
        self.__started=True
        self.__stoped=False

    def ReStart(self):
        if(self.__stoped):
            time_elapsed = self.__elapsed
        else:
            time_elapsed =  time.time() - self.__start_time
        self.Start()
        return time_elapsed
    def Stop(self):
        if(self.__started & (not self.__stoped)):
            self.__stoped=True
            time_elapsed =  time.time() - self.__start_time
            self.__elapsed = time_elapsed
    def Elapsed(self):
        if(self.__stoped):
            return self.__elapsed
        else:
            time_elapsed =  time.time() - self.__start_time
            return time_elapsed
