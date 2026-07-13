public class MonitorSmoke {
    private static final Object LOCK = new Object();

    private static boolean check() {
        if (Thread.holdsLock(LOCK)) {
            return false;
        }
        synchronized (LOCK) {
            if (!Thread.holdsLock(LOCK)) {
                return false;
            }
            synchronized (LOCK) {
                if (!Thread.holdsLock(LOCK)) {
                    return false;
                }
            }
            return Thread.holdsLock(LOCK);
        }
    }

    public static void main(String[] args) {
        if (check() && !Thread.holdsLock(LOCK)) {
            System.out.println("monitor ok");
        } else {
            System.out.println("monitor failed");
        }
    }
}
