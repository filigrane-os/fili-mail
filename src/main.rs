mod gui;

fn main() {
    // No argument: the window (Facteur). Everything else is the command line and the daemon, which never start Qt.
    if std::env::args().len() == 1 {
        std::process::exit(gui::run());
    }
    #[cfg(windows)]
    {
        // Windows reserves only 1 MiB for the executable's initial thread.
        // The shared CLI/backend dispatch futures need the same stack budget
        // as the Unix entry point, including in unoptimized native test builds.
        let result = std::thread::Builder::new()
            .name("fili-mail-main".into())
            .stack_size(8 * 1024 * 1024)
            .spawn(fili_mail::cli::run)
            .expect("start backend entry thread")
            .join();
        if let Err(panic) = result {
            std::panic::resume_unwind(panic);
        }
    }
    #[cfg(not(windows))]
    fili_mail::cli::run();
}
