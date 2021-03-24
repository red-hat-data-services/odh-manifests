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
from jhtest import JHStress

logging.basicConfig(level=logging.INFO)
_LOGGER = logging.getLogger()
_SCREENSHOT_DIR=f"{os.environ.get('ARTIFACT_SCREENSHOT_DIR', '/tmp')}"

class Del:
  def __init__(self, keep=string.digits):
    self.comp = dict((ord(c),c) for c in keep)
  def __getitem__(self, k):
    return self.comp.get(k)

class JHLoad():
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
        self.jhs = JHStress()        
        self.jhs.as_admin=self.as_admin
        self.jhs.preload_repos=self.preload_repos
        

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
        self.preload_repos = os.environ.get('JH_PRELOAD_REPOS', "https://github.com/red-hat-data-service/notebook-benchmarks")
        self.pushgateway_url = os.environ.get('PUSHGATEWAY_URL', "localhost:9091")
        
        self.registry = CollectorRegistry()
        self.epoch_gauge = Gauge(name='epoch_duration_seconds', documentation='epoch_value is the metric itself, the stuff in the {}s are tags',labelnames=["model","framework","date","epoch"],registry=self.registry)
        self.step_gauge = Gauge(name='step_during_milliseconds', documentation='step_during_milliseconds is the metric itself, the stuff in the {}s are tags',labelnames=["model","framework","date","epoch"],registry=self.registry)

        _LOGGER.info("PUSHGATEWAY_URL %s" % self.pushgateway_url)
        if not self.url:
            _LOGGER.error("You need to provide $JH_URL env var.")
            raise Exception("You need to provide $JH_URL env var.")

    def run(self):
        try:
            self.jhs.login()
            _LOGGER.info("Logged in")
            
            self.jhs.spawn()
            self.driver = self.jhs.driver
            _LOGGER.info("Spawned the server")
            tab = self.driver.window_handles[0]

            for notebook in self.notebooks:
                _LOGGER.info("NOTEBOOK: %s" % notebook)
                self.run_notebook(notebook, tab)
                _LOGGER.info("Notebook %s finished" % notebook)

            _LOGGER.info("Report Metrics to PushGateWay")
            self.report_metrics()
            self.jhs.stop()
            _LOGGER.info("Stopped the server")
        except Exception as e:
            _LOGGER.error(e)
            self.driver.get_screenshot_as_file(os.path.join(_SCREENSHOT_DIR, "exception.png"))
            raise e


    def run_notebook(self, notebook, tab):
        _LOGGER.info("Current URL:"+ self.driver.current_url)
        path = notebook.split("/")
     
        w = WebDriverWait(self.driver, 100)      
        _LOGGER.info("Current URL:"+ self.driver.current_url)
        auth_elem = w.until(EC.presence_of_element_located((By.XPATH, '//div[@id="notebook_list"]')))
        # auth_elem = w.until(EC.presence_of_element_located((By.XPATH, '/html/body/div[1]/div/form/input')))
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

        self.jhs.run_all_cells()

        output_data = w.until(EC.presence_of_all_elements_located((By.XPATH,'//div[@id="notebook-container"]/div[2]/div[2]//pre')))

        self.extract_result(output_data,framework)
        self.driver.close()
        self.driver.switch_to_window(tab)
        
        _LOGGER.info("Back to root folder")
        if len(path) > 1:
            for segment in path[:-1]:
                self.driver.back()
                _LOGGER.info(self.driver.current_url)

  
    def quit(self):
        self.driver.quit()

    def extract_result(self,selected_element,framework):
        _LOGGER.info("in push data")
        epoch_num=0
        epoch_value=0
        step_value=0
        data_line=False
        DD = Del()
        output_exist=False
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
                    output_exist=True
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
                    _LOGGER.info("epoch_num: %s" % epoch_num)
                    _LOGGER.info("epoch_value: %s" % epoch_value)
                    _LOGGER.info("step_value: %s" % step_value)
                    output_exist=True
                    self.add_metrics_data(framework,epoch_num,epoch_value,step_value)
                
        if not output_exist:
            raise Exception("Output data is wrong")

    def report_metrics(self):
        push_to_gateway(self.pushgateway_url, job='jupyterhub_load', registry=self.registry)

    def add_metrics_data(self, framework, epoch_num,epoch_value,step_value):
        current_time=time.time()
              
        self.epoch_gauge.labels("mnist-minimal",framework,current_time,epoch_num).set(epoch_value)
        self.step_gauge.labels("mnist-minimal",framework,current_time,epoch_num).set(step_value)

if __name__ == "__main__":
    jhl = JHLoad()
    jhl.run()
    jhl.quit()
