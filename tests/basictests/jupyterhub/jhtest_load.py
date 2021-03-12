import os
import sys
import time
import string
import time
import logging

from distutils.util import strtobool
from prometheus_client import CollectorRegistry, Gauge, push_to_gateway

from selenium import webdriver
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.chrome.options import Options  
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.support.select import Select

from selenium.common.exceptions import NoSuchElementException

logging.basicConfig(level=logging.INFO)
_LOGGER = logging.getLogger()
_SCREENSHOT_DIR=f"{os.environ.get('ARTIFACT_SCREENSHOT_DIR', '/tmp')}"

class Del:
  def __init__(self, keep=string.digits):
    self.comp = dict((ord(c),c) for c in keep)
  def __getitem__(self, k):
    return self.comp.get(k)

class JHStress():
    def __init__(self):
        self.load_config()
        chrome_options = Options()  
        if self.headless:
            chrome_options.add_argument("--headless")
            chrome_options.add_argument('--no-sandbox')
            chrome_options.add_argument('--window-size=1420,1080')
            chrome_options.add_argument('--disable-gpu')
            chrome_options.add_argument('--disable-dev-shm-usage')
            chrome_options.add_argument('--ignore-certificate-errors')
        self.driver = webdriver.Chrome(chrome_options=chrome_options)
        self.driver.get(self.url)
        _LOGGER.info("Using JupyterHub URL %s" % self.url)
        self.action = ActionChains(self.driver)
        _LOGGER.info("Config loaded, driver initialized")

    def load_config(self):

        self.url = os.environ.get('JH_URL')
        self.username = os.environ.get('JH_LOGIN_USER')
        self.password = os.environ.get('JH_LOGIN_PASS')
        self.login_provider = os.environ.get('OPENSHIFT_LOGIN_PROVIDER', 'htpasswd-provider')
        self.notebooks = os.environ.get('JH_NOTEBOOKS', "").split(",")
        self.user_name = os.environ.get('JH_USER_NAME', 'test-user1')
        self.spawner = {
            "image": os.environ.get('JH_NOTEBOOK_IMAGE', "s2i-tensorflow-notebook:v0.0.2"),
            "size": os.environ.get('JH_NOTEBOOK_SIZE', "Default"),
            "gpu": os.environ.get('JH_NOTEBOOK_GPU', "0"),
        }
        self.as_admin = strtobool(os.environ.get('JH_AS_ADMIN', 'False'))
        self.headless = strtobool(os.environ.get('JH_HEADLESS', 'False'))
        self.preload_repos = os.environ.get('JH_PRELOAD_REPOS', "https://github.com/Xaenalt/notebook-benchmarks")
        self.pushgateway_url = os.environ.get('PUSHGATEWAY_URL', "localhost:9091")
        
        self.registry = CollectorRegistry()
        self.epoch_gauge = Gauge(name='epoch_duration_seconds', documentation='epoch_value is the metric itself, the stuff in the {}s are tags',labelnames=["model","framework","date","epoch"],registry=self.registry)
        self.step_gauge = Gauge(name='step_during_milliseconds', documentation='step_during_milliseconds is the metric itself, the stuff in the {}s are tags',labelnames=["model","framework","date","epoch"],registry=self.registry)

        _LOGGER.info("PUSHGATEWAY_URL %s" % self.pushgateway_url)
        if not self.url:
            _LOGGER.error("You need to provide $JH_URL env var.")
            raise Exception("You need to provide $JH_URL env var.")

    def click_menu(self, button):
        cell_elem = self.driver.find_element(By.XPATH, '//a[text()="%s"]' % button)
        cell_elem.click()

    def openshift_login(self, username, password):
        username_elem = self.driver.find_element_by_id("inputUsername")
        username_elem.send_keys(username)
        password_elem = self.driver.find_element_by_id("inputPassword")
        password_elem.send_keys(password)
        login_elem = self.driver.find_element(By.XPATH, '//button[text()="Log in"]')
        login_elem.send_keys(Keys.RETURN)

    def run(self):
        try:
            self.login()
            _LOGGER.info("Logged in")
            
            self.spawn()
            _LOGGER.info("Spawned the server")
            tab = self.driver.window_handles[0]

            for notebook in self.notebooks:
                _LOGGER.info("NOTEBOOK: %s" % notebook)
                self.run_notebook(notebook, tab)
                _LOGGER.info("Notebook %s finished" % notebook)

            _LOGGER.info("Report Metrics to PushGateWay")
            # This is commented because there is no ways to access internal pushgateway from OSD.
            # But as soon as we find the way, this will be uncommented. 
            # self.report_metrics()
            self.stop()
            _LOGGER.info("Stopped the server")
        except Exception as e:
            _LOGGER.error(e)
            self.driver.get_screenshot_as_file(os.path.join(_SCREENSHOT_DIR, "exception.png"))
            raise e

    def deal_with_privacy_error(self):
        if "Privacy error" in self.driver.title:
            elem = self.driver.find_element_by_id("details-button")
            elem.send_keys(Keys.RETURN)
            elem = self.driver.find_element_by_id("proceed-link")
            elem.send_keys(Keys.RETURN)
        
    def login(self):
        self.deal_with_privacy_error()
        elem = self.driver.find_element_by_link_text("Sign in with OpenShift")
        elem.send_keys(Keys.RETURN)
        self.deal_with_privacy_error()

        if self.check_exists_by_xpath('//a[text()="%s"]' % self.login_provider):
            elem = self.driver.find_element_by_link_text(self.login_provider)
            elem.send_keys(Keys.RETURN)
            self.openshift_login(self.username, self.password)

        permissions_xpath = '//input[@value="Allow selected permissions"]'
        if self.check_exists_by_xpath(permissions_xpath):
            elem = spawn_elem = self.driver.find_element(By.XPATH, permissions_xpath)
            elem.send_keys(Keys.RETURN)
    
    def test_environment_variables(self):
        _LOGGER.info("Testing Environment Variables")
        self.add_environment_variable('foo', 'bar')
        self.add_environment_variable('foo1', 'bar1')
        self.remove_last_environment_variable()
        self.remove_last_environment_variable()
    
    def add_environment_variable(self, key, value):
        self.driver.implicitly_wait(10)
        add_button_elem = self.driver.find_element(By.XPATH, '//*[@id="root"]/div/header/form/form/button')
        add_button_elem.send_keys(Keys.RETURN)
        key_elem = self.driver.find_element(By.NAME, 'variable_name')
        value_elem = self.driver.find_element(By.NAME, 'variable_value')
        key_elem.clear()
        key_elem.send_keys(key)
        value_elem.clear()
        value_elem.send_keys(value)

    def remove_last_environment_variable(self):
        remove_button_elems = self.driver.find_elements(By.CLASS_NAME, 'btn-danger')
        elem = remove_button_elems[len(remove_button_elems) - 1]
        elem.send_keys(Keys.RETURN)

    def spawn(self):
        self.driver.implicitly_wait(10)
        image_drop = self.driver.find_element(By.XPATH, '//*[@id="ImageDropdownBtn"]')
        image_drop.send_keys(Keys.RETURN)

        self.driver.implicitly_wait(10)
        image_select = self.driver.find_element_by_id(self.spawner["image"])
        image_select.click()

        size_drop = self.driver.find_element(By.XPATH, '//*[@id="SizeDropdownBtn"]')
        size_drop.click()

        size_select = self.driver.find_element_by_id(self.spawner["size"])
        size_select.click()

        gpu_elem = self.driver.find_element(By.XPATH, '//*[@id="gpu-form"]')
        gpu_elem.clear()
        gpu_elem.send_keys(self.spawner['gpu'])

        self.test_environment_variables()

        time.sleep(0.5)

        self.add_environment_variable("JUPYTER_PRELOAD_REPOS", self.preload_repos)

        gpu_elem.send_keys(Keys.RETURN)

    def stop(self):
        self.driver.get(self.url+ "/hub/home")
        stop_elem = self.driver.find_element_by_id("stop")
        stop_elem.click()

    def run_notebook(self, notebook, tab):
        _LOGGER.info(self.driver.current_url)
        path = notebook.split("/")
     
        w = WebDriverWait(self.driver, 300)      

        auth_elem = w.until(EC.presence_of_element_located((By.XPATH, '//div[@id="notebook_list"]')))
        auth_elem.click()
        
        framework=""
        if len(path) > 1:
            for segment in path[:-1]:
                _LOGGER.info("segment: "+segment)
                if segment in ("tensorflow", "pytorch"):
                    framework=segment
                w = WebDriverWait(self.driver, 10)
                dir_elem = w.until(EC.presence_of_element_located((By.XPATH, '//span[text()="%s"]' % segment)))
                dir_elem.click()

        _LOGGER.info("Executing notebook %s" % path[-1])
        notebook_elem = w.until(EC.presence_of_element_located((By.XPATH, '//span[text()="%s"]' % path[-1])))
        notebook_elem.click()

        #Switch to new tab
        self.driver.switch_to_window(self.driver.window_handles[1])

        self.run_all_cells()

        output_data = w.until(EC.presence_of_all_elements_located((By.XPATH,'//div[@id="notebook-container"]/div[2]/div[2]//pre')))

        self.extract_result(output_data,framework)
        self.driver.close()
        self.driver.switch_to_window(tab)
        
        _LOGGER.info("Back to root folder")
        if len(path) > 1:
            for segment in path[:-1]:
                self.driver.back()
                _LOGGER.info(self.driver.current_url)

  
    def run_all_cells(self):
        try:
            w = WebDriverWait(self.driver, 30)
            element = w.until(EC.presence_of_element_located((By.XPATH, '//i[@id="kernel_indicator_icon"][@title="Kernel Idle"]')))
        except Exception as e:
            _LOGGER.error(e)
            raise e

        wait = WebDriverWait(self.driver, 10)
        elem = wait.until(EC.element_to_be_clickable((By.XPATH, '//a[text()="Cell"]')))

        self.click_menu("Cell")
        elem = self.driver.find_element_by_id("all_outputs")
        self.driver.execute_script("arguments[0].setAttribute('class','dropdown-submenu open')", elem)

        clear_elem = self.driver.find_element_by_id("clear_all_output")
        clear_elem.click()

        self.click_menu("Cell")
        self.click_menu("Run All")

        cells = self.driver.find_elements(By.XPATH, '//div[contains(@class, "cell code_cell")]')

        last = len(cells)
        wait_time = 600
        retries = int(wait_time/2)
        last_cell = None
        for i in range(0, retries):
            last_cell = self.driver.find_element(By.XPATH, '(//div[contains(@class, "cell code_cell")])[%d]//div[@class="prompt_container"]' % last)
            if last_cell.text == "In [*]:" or last_cell.text == "In [ ]:":
                time.sleep(2)
            else:
                break
        time.sleep(2)
        _LOGGER.info("Reached last cell, execution numbering: '%s'" % last_cell.text)

    def quit(self):
        self.driver.quit()

    def check_exists_by_xpath(self, xpath):
        try:
            self.driver.find_element_by_xpath(xpath)
        except NoSuchElementException:
            return False
        return True

    def extract_result(self,selected_element,framework):
        _LOGGER.info("in push data")
        epoch_num=0
        epoch_value=0
        step_value=0
        data_line=False
        DD = Del()
    
        if framework == "tensorflow":
            selected_data = selected_element[-2].text
            _LOGGER.info("output_data: %s" % selected_data)
            for line in selected_data.split('\n'):
                if data_line:
                    _LOGGER.info("in data_line")
                    data_line=False
                    data=line.split()
                    epoch_value=data[3].translate(DD)
                    step_value=data[4].translate(DD)
                    _LOGGER.info("epoch_num: %s" % epoch_num)
                    _LOGGER.info("epoch_value: %s" % epoch_value)
                    _LOGGER.info("step_value: %s" % step_value)
                    self.add_metrics_data(framework,epoch_num,epoch_value,step_value)
                    

                if "Epoch" in line:
                    _LOGGER.info("in Epoch")
                    epoch_num=line.split()[1].split('/')[0]
                    data_line=True
        else:
            selected_data = selected_element[-1].text
            _LOGGER.info("output_data: %s" % selected_data)
            for line in selected_data.split('\n'):
                if "Epoch" in line:
                    _LOGGER.info("in Epoch")
                    epoch_num=int(line.split()[1].translate(DD))+1
                    epoch_value=line.split()[4].split('.')[0].translate(DD)
                    step_value=line.split()[7].split('.')[0].translate(DD)
                    self.add_metrics_data(framework,epoch_num,epoch_value,step_value)
                    
    def report_metrics(self):
        push_to_gateway(self.pushgateway_url, job='jupyterhub_load', registry=self.registry)

    def add_metrics_data(self, framework, epoch_num,epoch_value,step_value):
        current_time=time.time()
              
        self.epoch_gauge.labels("mnist-minimal",framework,current_time,epoch_num).set(epoch_value)
        self.step_gauge.labels("mnist-minimal",framework,current_time,epoch_num).set(step_value)

if __name__ == "__main__":
    jhs = JHStress()
    jhs.run()
    jhs.quit()
