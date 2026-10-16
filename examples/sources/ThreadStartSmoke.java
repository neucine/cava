public class ThreadStartSmoke {
    private static int VALUE = 0;

    static class Worker extends Thread {
        @Override
        public void run() {
            VALUE = 42;
        }
    }

    public static void main(String[] args) throws Exception {
        Worker worker = new Worker();
        worker.start();
        Thread.sleep(50);

        boolean restartRejected = false;
        try {
            worker.start();
        } catch (IllegalThreadStateException expected) {
            restartRejected = true;
        }

        if (VALUE == 42 && restartRejected && !worker.isAlive()) {
            System.out.println("thread start ok");
        } else {
            System.out.println("thread start failed");
        }
    }
}
