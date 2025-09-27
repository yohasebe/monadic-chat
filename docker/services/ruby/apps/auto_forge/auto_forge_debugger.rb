# frozen_string_literal: true

require 'json'
require 'fileutils'

module AutoForge
  class Debugger
    def initialize(context = {})
      @context = context || {}
    end

    def debug_html(html_path, options = {})
      unless File.exist?(html_path)
        return {
          success: false,
          error: "HTML file not found: #{html_path}"
        }
      end

      # Check if Selenium container is available
      unless selenium_available?
        return {
          success: false,
          error: "Selenium container is not available. Please ensure it's running."
        }
      end

      # Create a temporary Python script for debugging
      debug_script = create_debug_script(html_path, options)

      # Execute the debug script
      result = execute_debug_script(debug_script, html_path)

      # Parse and return results
      format_debug_results(result)
    ensure
      # Clean up temporary files
      File.delete(debug_script) if debug_script && File.exist?(debug_script)
    end

    private

    def selenium_available?
      # Check if the Python container (which includes Selenium) is running
      `docker ps --format "{{.Names}}"`.include?("monadic_python")
    end

    def create_debug_script(html_path, options)
      script_path = File.join(Dir.tmpdir, "debug_html_#{Time.now.to_i}.py")

      script_content = <<~PYTHON
        #!/usr/bin/env python
        import sys
        import json
        import time
        from selenium import webdriver
        from selenium.webdriver.chrome.options import Options
        from selenium.webdriver.common.by import By
        from selenium.common.exceptions import WebDriverException, TimeoutException
        import os

        def debug_html(html_path):
            results = {
                'success': True,
                'errors': [],
                'warnings': [],
                'console_logs': [],
                'network_errors': [],
                'javascript_errors': [],
                'performance': {},
                'functionality_tests': []
            }

            chrome_options = Options()
            chrome_options.add_argument('--headless')
            chrome_options.add_argument('--no-sandbox')
            chrome_options.add_argument('--disable-dev-shm-usage')
            chrome_options.add_argument('--disable-gpu')
            chrome_options.set_capability('goog:loggingPrefs', {'browser': 'ALL', 'performance': 'ALL'})

            driver = None
            try:
                # Connect to Selenium container
                driver = webdriver.Remote(
                    command_executor='http://selenium:4444/wd/hub',
                    options=chrome_options
                )

                # Load the HTML file
                file_url = f"file://{html_path}"
                driver.get(file_url)

                # Wait for page to load
                time.sleep(2)

                # Check for JavaScript errors
                logs = driver.get_log('browser')
                for log in logs:
                    if log['level'] == 'SEVERE':
                        results['javascript_errors'].append({
                            'message': log['message'],
                            'timestamp': log['timestamp']
                        })
                    elif log['level'] == 'WARNING':
                        results['warnings'].append({
                            'message': log['message'],
                            'timestamp': log['timestamp']
                        })
                    else:
                        results['console_logs'].append({
                            'level': log['level'],
                            'message': log['message'],
                            'timestamp': log['timestamp']
                        })

                # Check page title
                if driver.title:
                    results['page_title'] = driver.title

                # Check for common UI elements
                results['functionality_tests'].append({
                    'test': 'Page loads without critical errors',
                    'passed': len(results['javascript_errors']) == 0
                })

                # Check for forms
                forms = driver.find_elements(By.TAG_NAME, 'form')
                if forms:
                    results['functionality_tests'].append({
                        'test': f'Found {len(forms)} form(s)',
                        'passed': True,
                        'count': len(forms)
                    })

                # Check for buttons
                buttons = driver.find_elements(By.TAG_NAME, 'button')
                inputs = driver.find_elements(By.CSS_SELECTOR, 'input[type="button"], input[type="submit"]')
                total_buttons = len(buttons) + len(inputs)
                if total_buttons > 0:
                    results['functionality_tests'].append({
                        'test': f'Found {total_buttons} button(s)',
                        'passed': True,
                        'count': total_buttons
                    })

                # Check for interactive elements
                interactive = driver.find_elements(By.CSS_SELECTOR, 'input, textarea, select, button, a[href]')
                results['functionality_tests'].append({
                    'test': f'Found {len(interactive)} interactive element(s)',
                    'passed': len(interactive) > 0,
                    'count': len(interactive)
                })

                # Execute simple JavaScript to test if JS is working
                try:
                    js_test = driver.execute_script("return typeof document !== 'undefined' && document.body !== null;")
                    results['functionality_tests'].append({
                        'test': 'JavaScript execution',
                        'passed': js_test
                    })
                except Exception as e:
                    results['functionality_tests'].append({
                        'test': 'JavaScript execution',
                        'passed': False,
                        'error': str(e)
                    })

                # Check viewport and responsive design
                viewport = driver.execute_script("return {width: window.innerWidth, height: window.innerHeight};")
                results['viewport'] = viewport

                # Performance metrics
                performance_timing = driver.execute_script("""
                    var timing = window.performance.timing;
                    return {
                        'loadTime': timing.loadEventEnd - timing.navigationStart,
                        'domReadyTime': timing.domContentLoadedEventEnd - timing.navigationStart,
                        'renderTime': timing.domComplete - timing.domLoading
                    };
                """)
                results['performance'] = performance_timing

            except TimeoutException as e:
                results['success'] = False
                results['errors'].append(f"Page load timeout: {str(e)}")
            except WebDriverException as e:
                results['success'] = False
                results['errors'].append(f"WebDriver error: {str(e)}")
            except Exception as e:
                results['success'] = False
                results['errors'].append(f"Unexpected error: {str(e)}")
            finally:
                if driver:
                    driver.quit()

            return results

        if __name__ == "__main__":
            html_path = sys.argv[1] if len(sys.argv) > 1 else None
            if not html_path:
                print(json.dumps({'success': False, 'errors': ['No HTML file path provided']}))
                sys.exit(1)

            results = debug_html(html_path)
            print(json.dumps(results, indent=2))
      PYTHON

      File.write(script_path, script_content)
      script_path
    end

    def execute_debug_script(script_path, html_path)
      # Make the HTML file accessible in the Python container
      shared_volume = ENV['SHARED_VOLUME'] || File.expand_path('~/monadic/data')
      temp_html = File.join(shared_volume, "temp_debug_#{Time.now.to_i}.html")
      FileUtils.cp(html_path, temp_html)

      # Execute the script in the Python container
      container_html_path = "/monadic/data/#{File.basename(temp_html)}"
      command = "cd /monadic/data && python #{File.basename(script_path)} #{container_html_path}"

      result = nil
      output = `docker exec monadic_python #{command} 2>&1`

      begin
        result = JSON.parse(output)
      rescue JSON::ParserError => e
        result = {
          'success' => false,
          'errors' => ["Failed to parse debug output: #{e.message}", "Raw output: #{output[0..500]}"]
        }
      end

      # Clean up temporary HTML file
      File.delete(temp_html) if File.exist?(temp_html)

      result
    end

    def format_debug_results(result)
      return { success: false, error: "No debug results" } unless result

      formatted = {
        success: result['success'],
        summary: []
      }

      # Add summary information
      if result['success']
        formatted[:summary] << "✅ Page loaded successfully"
      else
        formatted[:summary] << "❌ Page failed to load"
      end

      # JavaScript errors
      if result['javascript_errors'] && !result['javascript_errors'].empty?
        formatted[:javascript_errors] = result['javascript_errors']
        formatted[:summary] << "⚠️  Found #{result['javascript_errors'].length} JavaScript error(s)"
      else
        formatted[:summary] << "✅ No JavaScript errors detected"
      end

      # Warnings
      if result['warnings'] && !result['warnings'].empty?
        formatted[:warnings] = result['warnings']
        formatted[:summary] << "⚠️  Found #{result['warnings'].length} warning(s)"
      end

      # Functionality tests
      if result['functionality_tests']
        passed = result['functionality_tests'].count { |t| t['passed'] }
        total = result['functionality_tests'].length
        formatted[:tests] = result['functionality_tests']
        formatted[:summary] << "🧪 #{passed}/#{total} functionality tests passed"
      end

      # Performance metrics
      if result['performance'] && result['performance']['loadTime']
        load_time = result['performance']['loadTime']
        formatted[:performance] = result['performance']
        status = load_time < 1000 ? "⚡" : load_time < 3000 ? "🔄" : "🐌"
        formatted[:summary] << "#{status} Page load time: #{load_time}ms"
      end

      # Console logs (optional, only if verbose)
      formatted[:console_logs] = result['console_logs'] if result['console_logs'] && !result['console_logs'].empty?

      # Viewport information
      formatted[:viewport] = result['viewport'] if result['viewport']

      formatted
    end
  end
end