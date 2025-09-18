use crate::config::Config;
use crate::error::QcmError;
use crate::logger::Logger;
use headless_chrome::{Browser, LaunchOptions};
use std::time::Duration;
use std::net::TcpListener;
use std::sync::atomic::{AtomicU16, Ordering};
use std::sync::Arc;
use std::fs;
use std::path::Path;
use std::process::Command;
use tokio;
 
#[cfg(target_os = "windows")]
use crate::windows_session::WindowsSessionLauncher;
 
pub struct ChromeClient {
    config: Config,
    logger: Logger,
    port_counter: Arc<AtomicU16>,
}
 
impl ChromeClient {
    pub fn new(config: Config, logger: Logger) -> Self {
        Self {
            config,
            logger,
            port_counter: Arc::new(AtomicU16::new(9222))
        }
    }
 
    // Find an available port for Chrome debugging
    fn find_available_port(&self) -> Result<u16, QcmError> {
        let start_port = self.port_counter.fetch_add(1, Ordering::SeqCst);
        
        // Try ports from start_port to start_port + 100
        for offset in 0..100 {
            let port = start_port.wrapping_add(offset);
            if port < 9222 { continue; } // Ensure we don't go below 9222
            if port > 65535 { break; }    // Avoid invalid ports
            
            // Try to bind to this port to check if it's available
            if let Ok(listener) = TcpListener::bind(("127.0.0.1", port)) {
                drop(listener); // Release the port
                return Ok(port);
            }
        }
        
        Err(QcmError::Chrome("No available ports found for Chrome debugging".to_string()))
    }
 
    fn get_chrome_path(&self) -> Result<std::path::PathBuf, QcmError> {
        // Try common Chrome installation paths
        #[cfg(target_os = "windows")]
        let paths = [
            r"C:\Program Files\Google\Chrome\Application\chrome.exe",
            r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
            r"C:\Users\%USERNAME%\AppData\Local\Google\Chrome\Application\chrome.exe",
        ];
        
        #[cfg(target_os = "macos")]
        let paths = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
        ];
        
        #[cfg(target_os = "linux")]
        let paths = [
            "/usr/bin/google-chrome",
            "/usr/bin/chromium-browser",
            "/usr/bin/chromium",
        ];
 
        for path in &paths {
            let chrome_path = std::path::PathBuf::from(path);
            if chrome_path.exists() {
                return Ok(chrome_path);
            }
        }
 
        // Fallback: try to find Chrome in PATH
        if let Ok(output) = Command::new("which").arg("google-chrome").output() {
            if output.status.success() {
                let path_str = String::from_utf8_lossy(&output.stdout);
                let path = path_str.trim();
                return Ok(std::path::PathBuf::from(path));
            }
        }
 
        Err(QcmError::Chrome("Chrome executable not found".to_string()))
    }
 
    // Clean up old Chrome profile directories
    async fn cleanup_old_profiles(&self) -> Result<(), QcmError> {
        let sessions_dir = Path::new("C:\\PAM\\chrome_sessions");
        
        if !sessions_dir.exists() {
            return Ok(());
        }
 
        self.logger.debug("CLEANUP", "chrome_sessions", "START", "Starting Chrome profile cleanup")?;
        
        let mut cleaned_count = 0;
        let cutoff_time = std::time::SystemTime::now() - Duration::from_secs(3600); // 1 hour old
        
        if let Ok(entries) = fs::read_dir(sessions_dir) {
            for entry in entries {
                if let Ok(entry) = entry {
                    let path = entry.path();
                    if path.is_dir() {
                        // Check if directory is older than cutoff time
                        if let Ok(metadata) = entry.metadata() {
                            if let Ok(modified) = metadata.modified() {
                                if modified < cutoff_time {
                                    // Try to remove the directory
                                    if let Ok(_) = fs::remove_dir_all(&path) {
                                        cleaned_count += 1;
                                        self.logger.debug("CLEANUP", "chrome_sessions", "REMOVED",
                                            &format!("Removed old profile: {:?}", path.file_name()))?;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        self.logger.info("CLEANUP", "chrome_sessions", "COMPLETED",
            &format!("Cleaned up {} old Chrome profiles", cleaned_count))?;
        
        Ok(())
    }
 
    // Create and ensure Chrome profile directory exists
    async fn launch_chrome_standard(&self, profile_dir: &Path, port: u16) -> Result<Browser, QcmError> {
        use std::ffi::OsStr;
        
        let user_data_arg = format!("--user-data-dir={}", profile_dir.display());
        
        let launch_options = LaunchOptions::default_builder()
            .path(Some(self.get_chrome_path()?))
            .port(Some(port))
            .headless(false)
            .args(vec![
                OsStr::new(&user_data_arg),
                OsStr::new("--disable-web-security"),
                OsStr::new("--disable-features=VizDisplayCompositor"),
                OsStr::new("--start-maximized"),
                OsStr::new("--disable-infobars"),
                OsStr::new("--disable-dev-shm-usage"),
                OsStr::new("--disable-extensions"),
                OsStr::new("--disable-plugins"),
                OsStr::new("--disable-default-apps"),
                OsStr::new("--disable-popup-blocking"),
                OsStr::new("--disable-translate"),
                OsStr::new("--disable-background-timer-throttling"),
                OsStr::new("--disable-renderer-backgrounding"),
                OsStr::new("--disable-backgrounding-occluded-windows"),
                OsStr::new("--disable-component-extensions-with-background-pages"),
                OsStr::new("--no-first-run"),
                OsStr::new("--no-default-browser-check"),
                OsStr::new("--disable-ipc-flooding-protection"),
                OsStr::new("--disable-dev-tools"),
                OsStr::new("--disable-context-menu"),
                OsStr::new("--disable-menu-shortcut-keys"),
                OsStr::new(url),
            ])
            .build()
            .expect("Failed to build Chrome launch options");
 
        Browser::new(launch_options).map_err(|e| QcmError::Chrome(format!("Failed to launch Chrome: {}", e)))
    }
 
    #[cfg(target_os = "windows")]
    async fn launch_chrome_in_session(&self, session_id: u32, profile_dir: &Path, port: u16) -> Result<Browser, QcmError> {
        let chrome_path = self.get_chrome_path()?;
        
        // Build command line arguments
        let args = vec![
            format!("--remote-debugging-port={}", port),
            format!("--user-data-dir={}", profile_dir.display()),
            "--disable-web-security".to_string(),
            "--disable-features=VizDisplayCompositor".to_string(),
            "--start-maximized".to_string(),
            "--disable-infobars".to_string(),
            "--disable-dev-shm-usage".to_string(),
            "--disable-extensions".to_string(),
            "--disable-plugins".to_string(),
            "--disable-default-apps".to_string(),
            "--disable-popup-blocking".to_string(),
            "--disable-translate".to_string(),
            "--disable-background-timer-throttling".to_string(),
            "--disable-renderer-backgrounding".to_string(),
            "--disable-backgrounding-occluded-windows".to_string(),
            "--disable-component-extensions-with-background-pages".to_string(),
            "--no-first-run".to_string(),
            "--no-default-browser-check".to_string(),
            "--disable-ipc-flooding-protection".to_string(),
            "--disable-dev-tools".to_string(),
            "--disable-context-menu".to_string(),
            "--disable-menu-shortcut-keys".to_string(),
            url.to_string(),
        ];
 
        // Launch Chrome in the specified session
        let launcher = WindowsSessionLauncher::new();
        launcher.launch_in_session(session_id, &chrome_path.to_string_lossy(), &args)
            .map_err(|e| QcmError::Chrome(format!("Failed to launch Chrome in session {}: {}", session_id, e)))?;
 
        // Wait for Chrome to start
        tokio::time::sleep(Duration::from_millis(2000)).await;
 
        // Connect to the Chrome instance via remote debugging
        let ws_url = format!("ws://127.0.0.1:{}", port);
        
        // Try to connect to Chrome debugging interface
        let mut retries = 0;
        const MAX_RETRIES: u32 = 10;
        
        loop {
            match Browser::connect(ws_url.clone()) {
                Ok(browser) => return Ok(browser),
                Err(e) if retries < MAX_RETRIES => {
                    retries += 1;
                    // Use log crate instead of Logger instance for internal debug messages
                    log::debug!("Session {} - Retry {} connecting to Chrome on port {}: {}",
                               session_id, retries, port, e);
                    tokio::time::sleep(Duration::from_millis(500)).await;
                },
                Err(e) => {
                    return Err(QcmError::Chrome(format!(
                        "Failed to connect to Chrome in session {} after {} retries: {}",
                        session_id, MAX_RETRIES, e
                    )));
                }
            }
        }
    }
 
    fn ensure_profile_directory(&self, _uuid: Option<&str>, session_id: Option<u32>) -> Result<std::path::PathBuf, QcmError> {
        let user_data_dir = if let Some(session_id) = session_id {
            format!("C:\\PAM\\chrome_sessions\\session_{}", session_id)
        } else {
            "C:\\PAM\\chrome_sessions\\default".to_string()
        };
        
        // Create the directory if it doesn't exist
        let sessions_dir = Path::new("C:\\PAM\\chrome_sessions");
        if !sessions_dir.exists() {
            fs::create_dir_all(sessions_dir)
                .map_err(|e| QcmError::Chrome(format!("Failed to create sessions directory: {}", e)))?;
        }
        
        let profile_dir = Path::new(&user_data_dir);
        if !profile_dir.exists() {
            fs::create_dir_all(profile_dir)
                .map_err(|e| QcmError::Chrome(format!("Failed to create profile directory: {}", e)))?;
        }
        
        Ok(profile_dir.to_path_buf())
    }
 
    pub async fn auto_login(
        &self,
        url: &str,
        username: &str,
        password: &str,
        session_id: Option<u32>,
        session_user: Option<&str>,
        _uuid: Option<&str>
    ) -> Result<(), QcmError> {
        let session_info = match (session_id, session_user) {
            (Some(sid), Some(user)) => format!(" (Session: {} - {})", sid, user),
            (Some(sid), None) => format!(" (Session: {})", sid),
            _ => String::new(),
        };
        
        self.logger.info("WEB", url, "STARTING",
            &format!("Initiating Chrome auto-login{}", session_info))?;
 
        if let Some(session_id) = session_id {
            self.logger.info("WEB", url, "SESSION_INFO",
                &format!("Target session: {} (user: {})",
                    session_id,
                    session_user.unwrap_or("unknown")))?;
        }
 
        // Clean up old profiles before starting new session
        self.cleanup_old_profiles().await?;
 
        // Find available port for Chrome debugging
        let debug_port = self.find_available_port()?;
        self.logger.debug("WEB", url, "PORT_ALLOCATED",
            &format!("Using Chrome debug port: {}", debug_port))?;
 
        self.logger.debug("WEB", url, "LAUNCHING", "Starting Chrome with remote debugging")?;
 
        // Create session-specific user data directory to avoid conflicts
        let user_data_dir = self.ensure_profile_directory(session_user, session_id)?;
        
        // Launch Chrome in the correct session if session_id is provided
        #[cfg(target_os = "windows")]
        let browser = if let Some(session_id) = session_id {
            self.logger.info("WEB", url, "SESSION_LAUNCH",
                &format!("Launching Chrome in session {} for user {}",
                    session_id, session_user.unwrap_or("unknown")))?;
            
            self.launch_chrome_in_session(session_id, &user_data_dir, debug_port).await?
        } else {
            self.logger.info("WEB", url, "STANDARD_LAUNCH", "Launching Chrome in current session")?;
            self.launch_chrome_standard(&user_data_dir, debug_port).await?
        };
 
        #[cfg(not(target_os = "windows"))]
        let browser = {
            self.logger.info("WEB", url, "STANDARD_LAUNCH", "Launching Chrome (non-Windows)")?;
            self.launch_chrome_standard(&user_data_dir, debug_port).await?
        };
 
        // Set up timeout for the entire login process (10 minutes max)
        let login_timeout = Duration::from_secs(600);
        let cleanup_result = tokio::time::timeout(login_timeout, async {
            // Wait for Chrome to start and the app mode to load the page
            tokio::time::sleep(Duration::from_secs(3)).await;
 
            self.logger.debug("WEB", url, "NAVIGATING", "Chrome launched in app mode")?;
 
        // Get the first existing tab (app mode should have loaded the URL automatically)
        let tab = {
            let tabs = browser.get_tabs();
            let tabs_lock = tabs.lock().unwrap();
            if let Some(first_tab) = tabs_lock.get(0) {
                first_tab.clone()
            } else {
                return Err(QcmError::Chrome("No tab found in Chrome instance".to_string()));
            }
        };
 
        self.logger.debug("WEB", url, "NAVIGATE_OK", "App mode launched with URL, page should be loading")?;
 
        // Wait for page to load
        tokio::time::sleep(Duration::from_secs(3)).await;
 
        // Check if page is fully loaded
        match tab.wait_until_navigated() {
            Ok(_) => {
                self.logger.debug("WEB", url, "PAGE_LOAD_OK", "Page loaded successfully")?;
            }
            Err(e) => {
                self.logger.debug("WEB", url, "PAGE_LOAD_WARNING", &format!("Wait navigation warning (may be normal): {}", e))?;
            }
        }
 
        // Wait a bit more for dynamic content
        tokio::time::sleep(Duration::from_secs(2)).await;
 
        self.logger.debug("WEB", url, "INJECTING", "Injecting credentials into form fields")?;
 
        // Try common username field selectors
        let username_selectors = vec![
            "input[name='user']", // Palo Alto username field (put first to try it early)
            "input[name='username']",
            "input[name='login']",
            "input[name='email']",
            "input[type='email']",
            "input[type='text'][name*='user']",
            "input[type='text'][name*='login']",
            "input[id='username']",
            "input[id='login']",
            "input[id='user']",
            "input[id='email']",
            "#username",
            "#login",
            "#user",
            "#email",
            ".username",
            ".login",
            ".user",
            ".email",
            "input[placeholder*='username' i]",
            "input[placeholder*='email' i]",
            "input[placeholder*='user' i]",
            "input[placeholder*='login' i]",
            "input#wp-user-login", // WordPress login field
        ];
 
        let mut username_filled = false;
        for selector in &username_selectors {
            self.logger.debug("WEB", url, "USERNAME_TRY", &format!("Trying username selector: {}", selector))?;
            if let Ok(element) = tab.find_element(selector) {
                self.logger.debug("WEB", url, "USERNAME_FOUND", &format!("Found element with selector: {}", selector))?;
                tokio::time::sleep(Duration::from_secs(1)).await;
                if element.type_into(username).is_ok() {
                    tokio::time::sleep(Duration::from_secs(1)).await;
                    self.logger.debug("WEB", url, "USERNAME", &format!("Filled username using selector: {}", selector))?;
                    username_filled = true;
                    break;
                }
            }
        }
 
        if !username_filled {
            return Err(QcmError::Chrome("Could not find username field".to_string()));
        }
 
        // Try common password field selectors
        let password_selectors = vec![
            "input[name='passwd']", // Palo Alto password field (put first to try it early)
            "input[name='password']",
            "input[name='pass']",
            "input[type='password']",
            "input[id='password']",
            "input[id='passwd']",
            "input[id='pass']",
            "#password",
            "#passwd",
            "#pass",
            ".password",
            ".passwd",
            ".pass",
            "input[placeholder*='password' i]",
            "input[placeholder*='pass' i]",
            "input#wp-pass", // WordPress password field
        ];
 
        let mut password_filled = false;
        for selector in &password_selectors {
            if let Ok(element) = tab.find_element(selector) {
                tokio::time::sleep(Duration::from_secs(1)).await;
                if element.type_into(password).is_ok() {
                    tokio::time::sleep(Duration::from_secs(1)).await;
                    self.logger.debug("WEB", url, "PASSWORD", &format!("Filled password using selector: {}", selector))?;
                    password_filled = true;
                    break;
                }
            }
        }
 
        if !password_filled {
            return Err(QcmError::Chrome("Could not find password field".to_string()));
        }
 
        // Try to find and click login button
        let login_selectors = vec![
            "input[type='submit']",
            "button[type='submit']",
            "input[value*='login' i]",
            "input[value*='sign in' i]",
            "button:contains('Login')",
            "button:contains('Sign In')",
            "button:contains('Submit')",
            "#login",
            "#signin",
            ".login",
            ".signin",
            "input#wp-submit", // WordPress login button
            "input[value*='Log In']", // Palo Alto login button
            "button[value*='Log In']", // Palo Alto login button
            "input[name='pda.login']", // Palo Alto login button
        ];
 
        let mut login_clicked = false;
        for selector in &login_selectors {
            if let Ok(element) = tab.find_element(selector) {
                tokio::time::sleep(Duration::from_secs(1)).await;
                if element.click().is_ok() {
                    self.logger.debug("WEB", url, "SUBMIT", &format!("Clicked login button using selector: {}", selector))?;
                    login_clicked = true;
                    break;
                }
            }
        }
 
        if !login_clicked {
            // Try pressing Enter as fallback
            if let Ok(_element) = tab.find_element("input[type='password']") {
                // Try using JavaScript to press Enter or submit form
                if let Err(_) = tab.evaluate("document.querySelector('input[type=\"password\"]').dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter'}))", false) {
                    // If Enter doesn't work, try JavaScript submit
                    let _ = tab.evaluate("document.querySelector('input[type=\"password\"]').form.submit()", false);
                    self.logger.debug("WEB", url, "SUBMIT", "Submitted form via JavaScript as fallback")?;
                } else {
                    self.logger.debug("WEB", url, "SUBMIT", "Submitted form via Enter key")?;
                }
            } else {
                self.logger.debug("WEB", url, "SUBMIT_SKIP", "No submit button found and no password field for fallback")?;
            }
        }
 
        // Wait for potential redirect or page change
        self.logger.debug("WEB", url, "WAITING", "Waiting for page redirect/change")?;
        tokio::time::sleep(Duration::from_secs(5)).await;
 
        // Check if login was successful by looking for common success indicators
        if let Ok(_) = tab.find_element("input[type='password']") {
            self.logger.debug("WEB", url, "LOGIN_STATUS", "Still on login page - login may have failed")?;
        } else {
            self.logger.debug("WEB", url, "LOGIN_STATUS", "Redirected away from login page - login likely successful")?;
        }
 
        // Keep Chrome open for a limited time (5 minutes) then auto-cleanup
        self.logger.debug("WEB", url, "KEEPING_OPEN", "Keeping Chrome open for 5 minutes then auto-cleanup")?;
        
        // Keep Chrome open for 5 minutes, checking every 30 seconds
        let mut remaining_time = 300; // 5 minutes in seconds
        while remaining_time > 0 {
            tokio::time::sleep(Duration::from_secs(30)).await;
            remaining_time -= 30;
            
            // Try to check if browser is still alive
            if browser.get_tabs().lock().unwrap().is_empty() {
                self.logger.debug("WEB", url, "CLEANUP", "Browser was closed manually")?;
                return Ok(());
            }
            
            self.logger.debug("WEB", url, "TIMER",
                &format!("Auto-cleanup in {} seconds", remaining_time))?;
        }
        
        self.logger.debug("WEB", url, "AUTO_CLEANUP", "Auto-cleanup timeout reached")?;
        Ok(())
        
        }).await;
 
        // Handle timeout or completion
        match cleanup_result {
            Ok(result) => {
                self.logger.info("WEB", url, "COMPLETED", "Login process completed normally")?;
                result
            },
            Err(_) => {
                self.logger.info("WEB", url, "TIMEOUT", "Login process timed out after 10 minutes")?;
                Ok(()) // Return ok since we want to cleanup gracefully
            }
        }
    }
}
 
 
