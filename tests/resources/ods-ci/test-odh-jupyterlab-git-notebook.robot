*** Settings ***
Default Tags     OpenDataHub
Resource         ${RESOURCE_PATH}/ODS.robot
Resource         ${RESOURCE_PATH}/Common.robot
Library          DebugLibrary

Suite Teardown   End Web Test


*** Variables ***
${ODH_JUPYTERHUB_URL}   https://jupyterhub-opendatahub-jupyterhub.apps.my-cluster.test.redhat.com


*** Test Cases ***
Can Launch Jupyterhub
  Open Browser  ${ODH_JUPYTERHUB_URL}  browser=${BROWSER.NAME}  options=${BROWSER.OPTIONS}

Can Login to Jupyterhub
  Login To Jupyterhub  ${TEST_USER.USERNAME}  ${TEST_USER.PASSWORD}  ${TEST_USER.AUTH_TYPE}
  ${authorization_required} =  Is Service Account Authorization Required
  Run Keyword If  ${authorization_required}  Authorize jupyterhub service account
  Wait Until Page Contains Element  xpath://span[@id='jupyterhub-logo']

Can Spawn Notebook
  # We need to skip this testcase if the user has an existing pod
  Fix Spawner Status
  Select Notebook Image  s2i-generic-data-science-notebook
  Spawn Notebook

Can Launch Tensorflow Load Test Notebook

  Wait for JupyterLab Splash Screen  timeout=30
  Maybe Select Kernel
  ${is_launcher_selected} =  Run Keyword And Return Status  JupyterLab Launcher Tab Is Selected
  Run Keyword If  not ${is_launcher_selected}  Open JupyterLab Launcher
  Launch a new JupyterLab Document
  Close Other JupyterLab Tabs

  Maybe Open JupyterLab Sidebar  File Browser
  Navigate Home In JupyterLab Sidebar
  Open With JupyterLab Menu  Git  Clone a Repository
  Input Text  //div[.="Clone a repo"]/../div[contains(@class, "jp-Dialog-body")]//input  https://github.com/red-hat-data-services/notebook-benchmarks
  Click Element  xpath://div[.="CLONE"]

  Sleep  5
  Open With JupyterLab Menu  File  Open from Path…
  Input Text  //div[.="Open Path"]/../div[contains(@class, "jp-Dialog-body")]//input  notebook-benchmarks/tensorflow/TensorFlow-MNIST-Minimal.ipynb
  Click Element  xpath://div[.="Open"]

  Capture Page Screenshot

  Wait Until TensorFlow-MNIST-Minimal.ipynb JupyterLab Tab Is Selected
  Close Other JupyterLab Tabs

  Open With JupyterLab Menu  Run  Run All Cells
  Wait Until JupyterLab Code Cell Is Not Active
  Capture Page Screenshot
  JupyterLab Code Cell Error Output Should Not Be Visible

  Capture Page Screenshot
  #Get the text of the last output cell
  ${output} =  Get Text  (//div[contains(@class,"jp-OutputArea-output")])[last()]
  Should Not Match  ${output}  ERROR*

Can Launch Pytorch Load Test Notebook
  Sleep  5
  Open With JupyterLab Menu  File  Open from Path…
  Input Text  //div[.="Open Path"]/../div[contains(@class, "jp-Dialog-body")]//input  notebook-benchmarks/pytorch/PyTorch-MNIST-Minimal.ipynb
  Click Element  xpath://div[.="Open"]

  Capture Page Screenshot

  Wait Until PyTorch-MNIST-Minimal.ipynb JupyterLab Tab Is Selected
  Close Other JupyterLab Tabs

  Open With JupyterLab Menu  Run  Run All Cells
  Wait Until JupyterLab Code Cell Is Not Active
#  Capture Page Screenshot
#  JupyterLab Code Cell Error Output Should Not Be Visible

  Capture Page Screenshot
  #Get the text of the last output cell
  ${output} =  Get Text  (//div[contains(@class,"jp-OutputArea-output")])[last()]
  Should Not Match  ${output}  ERROR*

  Logout JupyterLab

