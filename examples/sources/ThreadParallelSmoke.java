public class ThreadParallelSmoke {
    private static final Object LOCK = new Object();
    private static int ready;
    private static int result;
    private static volatile boolean go;
    private static volatile boolean failed;

    private static class Initialized {
        static int value = initialize();

        static int initialize() {
            int sum = 0;
            for (int index = 0; index < 30000; index++) {
                sum += index & 3;
            }
            return sum - 44958;
        }
    }

    private static class Worker extends Thread {
        public void run() {
            synchronized (LOCK) {
                ready++;
            }
            while (!go) {
                Thread.yield();
            }
            int initialized = Initialized.value;
            int[] values = new int[4];
            for (int index = 0; index < 10000; index++) {
                values[index & 3] = index;
            }
            if (initialized != 42 || values[3] != 9999) {
                failed = true;
            }
            synchronized (LOCK) {
                result += initialized;
            }
        }
    }

    public static void main(String[] args) throws Exception {
        Worker first = new Worker();
        Worker second = new Worker();
        first.start();
        second.start();
        boolean started = false;
        while (!started) {
            synchronized (LOCK) {
                started = ready == 2;
            }
            Thread.yield();
        }
        go = true;
        first.join();
        second.join();
        if (failed || result != 84) {
            throw new RuntimeException("parallel execution failed");
        }
        System.out.println("parallel execution ok");
    }
}
