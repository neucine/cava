public class SynchronizedMethodSmoke {
    private static int total;
    private static volatile boolean release;

    private static synchronized void incrementStatic() {
        if (!Thread.holdsLock(SynchronizedMethodSmoke.class)) throw new AssertionError();
        int previous = total;
        Thread.yield();
        total = previous + 1;
    }

    private static final class Counter {
        int value;
        volatile boolean entered;

        synchronized void increment() {
            incrementNested();
        }

        synchronized void incrementNested() {
            if (!Thread.holdsLock(this)) throw new AssertionError();
            int previous = value;
            Thread.yield();
            value = previous + 1;
        }

        synchronized void fail() {
            if (!Thread.holdsLock(this)) throw new AssertionError();
            throw new IllegalStateException();
        }

        synchronized void awaitRelease() {
            entered = true;
            while (!release) Thread.yield();
            try { Thread.sleep(1); } catch (InterruptedException exception) {
                throw new AssertionError();
            }
            if (!Thread.holdsLock(this)) throw new AssertionError();
        }
    }

    private static final class Worker extends Thread {
        private final Counter counter;
        private final Counter independent;
        Worker(Counter counter, Counter independent) {
            this.counter = counter;
            this.independent = independent;
        }
        public void run() {
            try { counter.fail(); } catch (IllegalStateException expected) { }
            if (Thread.holdsLock(counter)) throw new AssertionError();
            for (int index = 0; index < 100; index++) {
                counter.increment();
                if (Thread.holdsLock(counter)) throw new AssertionError();
                if ((index & 1) == 0) incrementStatic();
                else synchronized (SynchronizedMethodSmoke.class) {
                    int previous = total;
                    Thread.yield();
                    total = previous + 1;
                }
            }
            independent.awaitRelease();
        }
    }

    public static void main(String[] arguments) throws InterruptedException {
        Counter counter = new Counter();
        Counter left = new Counter();
        Counter right = new Counter();
        Worker first = new Worker(counter, left);
        Worker second = new Worker(counter, right);
        first.start();
        second.start();
        while (!left.entered || !right.entered) Thread.yield();
        release = true;
        first.join();
        second.join();
        if (counter.value != 200 || total != 200) throw new AssertionError();
        System.out.println("synchronized methods ok");
    }
}
