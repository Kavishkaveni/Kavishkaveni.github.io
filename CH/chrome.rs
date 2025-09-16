use crate::config::Config;
use crate::error::QcmError;
use crate::logger::Logger;
use headless_chrome::{Browser, LaunchOptions};
use std::time::Duration;
use tokio;

pub struct ChromeClient {
    config: Config,
    logger: Logger,
}

impl ChromeClient {
    pub fn new(config: Config, logger: Logger) -> Self {
        Self { config, logger }
    }

    

    pub async fn auto_login(&self, url: &str, username: &str, password: &str) -> Result<(), QcmError> {
        self.logger.info("WEB", url, "STARTING", "Initiating Chrome auto-login")?;

        self.logger.debug("WEB", url, "LAUNCHING", "Starting Chrome with remote debugging")?;

        // Launch Chrome browser in app mode with developer tools disabled
        use std::ffi::OsStr;
        let app_url = format!("--app={}", url);
        let launch_options = LaunchOptions::default_builder()
            .headless(false)
            .port(Some(9222))
            .args(vec![
                OsStr::new(&app_url),                    // App mode with URL (hides URL bar)
                OsStr::new("--disable-web-security"),   // Allow cross-origin requests
                OsStr::new("--disable-features=VizDisplayCompositor"), // Better compatibility
                OsStr::new("--start-maximized"),        // Start maximized
                OsStr::new("--disable-infobars"),       // Hide info bars
                OsStr::new("--disable-dev-shm-usage"),  // Disable dev shared memory
                OsStr::new("--disable-extensions"),     // Disable extensions
                OsStr::new("--disable-plugins"),        // Disable plugins
                OsStr::new("--disable-default-apps"),   // Disable default apps
                OsStr::new("--disable-popup-blocking"), // Disable popup blocking
                OsStr::new("--disable-translate"),      // Disable translate
                OsStr::new("--disable-background-timer-throttling"), // Disable background throttling
                OsStr::new("--disable-renderer-backgrounding"), // Disable renderer backgrounding
                OsStr::new("--disable-backgrounding-occluded-windows"), // Disable backgrounding
                OsStr::new("--disable-component-extensions-with-background-pages"), // Disable component extensions
                OsStr::new("--no-first-run"),           // Skip first run experience
                OsStr::new("--no-default-browser-check"), // Skip default browser check
                OsStr::new("--disable-ipc-flooding-protection"), // Disable IPC flooding protection
                OsStr::new("--disable-dev-tools"),      // Disable developer tools
                OsStr::new("--disable-context-menu"),   // Disable right-click context menu
                OsStr::new("--disable-menu-shortcut-keys"), // Disable keyboard shortcuts for menus
            ])
            .build()
            .expect("Couldn't find appropriate Chrome binary.");

        let browser = Browser::new(launch_options)
            .map_err(|e| QcmError::Chrome(format!("Failed to launch Chrome: {}", e)))?;

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

        // Keep Chrome open longer to see the login result
        self.logger.debug("WEB", url, "KEEPING_OPEN", "Keeping Chrome open - you can manually close it when done")?;
        
        // Keep Chrome open indefinitely - let user close manually
        // The browser will stay open until manually closed or service is stopped
        loop {
            tokio::time::sleep(Duration::from_secs(60)).await; // Check every minute
            
            // Try to check if browser is still alive
            if browser.get_tabs().lock().unwrap().is_empty() {
                self.logger.debug("WEB", url, "CLEANUP", "Browser was closed manually")?;
                break;
            }
        }

        Ok(())
    }
}
