public class ThreadSynchronizationSmoke {
    private static final Object LOCK = new Object();
    private static int value;
    private static boolean identityFailed;

    private static class Worker extends Thread {
        public void run() {
            if (Thread.currentThread() != this) {
                synchronized (LOCK) {
                    identityFailed = true;
                }
            }
            for (int index = 0; index < 200; index++) {
                synchronized (LOCK) {
                    int before = value;
                    Thread.yield();
                    value = before + 1;
                }
            }
        }
    }

    public static void main(String[] args) throws Exception {
        Worker first = new Worker();
        Worker second = new Worker();
        first.start();
        second.start();
        first.join();
        second.join();
        if (value != 400 || identityFailed) {
            throw new RuntimeException("thread synchronization failed");
        }
        System.out.println("thread synchronization ok");
    }
}
