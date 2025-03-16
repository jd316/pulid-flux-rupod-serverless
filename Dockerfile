FROM timpietruskyblibla/runpod-worker-comfy:3.4.0-flux1-dev

# Install system dependencies
RUN apt-get update && apt-get install -y \
    unzip \
    wget \
    git \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install custom nodes
WORKDIR /comfyui
RUN cd custom_nodes && \
    git clone git://github.com/LiamCX/ComfyUI-GGUF-Loader.git && \
    git clone git://github.com/vxid/comfyui_pulid_flux_ll && \
    git clone git://github.com/rgthree/rgthree-comfy && \
    git clone git://github.com/pythongosssss/ComfyUI-Custom-Scripts

# Create required directories
RUN mkdir -p /comfyui/models/pulid_flux && \
    mkdir -p /comfyui/models/insightface && \
    mkdir -p /comfyui/models/loras && \
    mkdir -p /comfyui/input

# Download Flux GGUF model
RUN wget -O /comfyui/models/FLUX1/flux1-dev-Q4_0.gguf https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/gguf/flux1-dev-Q4_0.gguf

# Download PuLID Flux models
RUN wget -O /comfyui/models/pulid_flux/pulid_flux_v0.9.1.safetensors https://huggingface.co/aloneill/pulid_flux/resolve/main/pulid_flux_v0.9.1.safetensors

# Download EVA CLIP model
RUN wget -O /comfyui/models/pulid_flux/model.safetensors https://huggingface.co/QuanTrieuPham/EvaLarge/resolve/main/model.safetensors

# Download InsightFace models
RUN wget -O /comfyui/models/insightface/buffalo_l.zip https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip && \
    unzip /comfyui/models/insightface/buffalo_l.zip -d /comfyui/models/insightface/ && \
    rm /comfyui/models/insightface/buffalo_l.zip

# Download FLUX Realism LORA
RUN wget -O /comfyui/models/loras/flux_realism_lora.safetensors https://huggingface.co/aloneill/flux-loras/resolve/main/flux_realism_lora.safetensors

# Download NSFW Master Flux LoRA from Civitai
RUN wget -O /comfyui/models/loras/NSFW_master.safetensors https://civitai.com/api/download/models/746602

# Install RunPod Python SDK
RUN pip install runpod

# Copy the default workflow file
COPY FLUX_LORA_PULID5_API.json /comfyui/default_workflow.json

# Create the RunPod handler script
RUN echo '#!/usr/bin/env python3\n\
import os\n\
import time\n\
import json\n\
import base64\n\
import requests\n\
import subprocess\n\
import runpod\n\
import uuid\n\
import random\n\
from pathlib import Path\n\
\n\
# Default workflow template\n\
DEFAULT_WORKFLOW_PATH = "/comfyui/default_workflow.json"\n\
\n\
# Start ComfyUI in the background\n\
def start_comfyui():\n\
    # Create the extra_model_paths.yaml file\n\
    with open("/comfyui/extra_model_paths.yaml", "w") as f:\n\
        f.write("pulid_flux: /comfyui/models/pulid_flux\\n")\n\
        f.write("insightface: /comfyui/models/insightface\\n")\n\
        f.write("loras: /comfyui/models/loras\\n")\n\
    \n\
    # Start ComfyUI as a background process\n\
    subprocess.Popen(["python", "/comfyui/main.py", "--listen", "0.0.0.0", "--port", "8188", "--disable-auto-launch"])\n\
    \n\
    # Wait for ComfyUI to start up\n\
    max_retries = 30\n\
    retries = 0\n\
    while retries < max_retries:\n\
        try:\n\
            response = requests.get("http://127.0.0.1:8188/system_stats")\n\
            if response.status_code == 200:\n\
                print("ComfyUI is running!")\n\
                return True\n\
        except:\n\
            pass\n\
        \n\
        retries += 1\n\
        time.sleep(1)\n\
    \n\
    print("Failed to start ComfyUI")\n\
    return False\n\
\n\
# Save an image from base64\n\
def save_image_from_base64(base64_data, input_dir="/comfyui/input"):\n\
    if not os.path.exists(input_dir):\n\
        os.makedirs(input_dir)\n\
    \n\
    image_data = base64.b64decode(base64_data)\n\
    image_filename = f"{uuid.uuid4()}.jpg"\n\
    image_path = os.path.join(input_dir, image_filename)\n\
    \n\
    with open(image_path, "wb") as f:\n\
        f.write(image_data)\n\
    \n\
    return image_filename\n\
\n\
# Load the default workflow template\n\
def load_default_workflow():\n\
    try:\n\
        with open(DEFAULT_WORKFLOW_PATH, "r") as f:\n\
            return json.load(f)\n\
    except Exception as e:\n\
        print(f"Error loading default workflow: {e}")\n\
        # Return a minimal default workflow if file is missing\n\
        return {}\n\
\n\
# Convert UI workflow JSON to API workflow JSON format\n\
def convert_ui_to_api_format(ui_workflow_json):\n\
    api_workflow = {}\n\
    \n\
    # Check if this is already in API format (no nodes/links fields)\n\
    if "nodes" not in ui_workflow_json:\n\
        return ui_workflow_json\n\
    \n\
    # Process each node from the UI format\n\
    for node in ui_workflow_json.get("nodes", []):\n\
        node_id = str(node["id"])\n\
        node_data = {\n\
            "class_type": node.get("type", ""),\n\
            "inputs": {}\n\
        }\n\
        \n\
        # Add metadata if available\n\
        if "title" in node:\n\
            node_data["_meta"] = {"title": node["title"]}\n\
        \n\
        # Process widget values (direct inputs)\n\
        if "widgets_values" in node:\n\
            widget_names = [input_data.get("name") for input_data in node.get("inputs", [])]\n\
            # Map widget values to input names\n\
            for i, value in enumerate(node.get("widgets_values", [])):\n\
                if i < len(widget_names):\n\
                    node_data["inputs"][widget_names[i]] = value\n\
                else:\n\
                    # If we can\'t find a name, use a generic one\n\
                    node_data["inputs"][f"param_{i}"] = value\n\
        \n\
        # Process node connections from links\n\
        for link in ui_workflow_json.get("links", []):\n\
            # Format: [link_id, from_node, from_slot, to_node, to_slot, link_type]\n\
            if len(link) >= 6 and link[3] == node["id"]:  # If this node is the target\n\
                to_slot = link[4]\n\
                from_node = str(link[1])\n\
                from_slot = link[2]\n\
                \n\
                # Find the input name for this slot\n\
                input_name = None\n\
                for i, input_data in enumerate(node.get("inputs", [])):\n\
                    if i == to_slot:\n\
                        input_name = input_data.get("name")\n\
                        break\n\
                \n\
                if input_name:\n\
                    node_data["inputs"][input_name] = [from_node, from_slot]\n\
        \n\
        api_workflow[node_id] = node_data\n\
    \n\
    return api_workflow\n\
\n\
# Update the workflow with a prompt and reference image\n\
def update_workflow_with_prompt_and_image(workflow_json, prompt=None, reference_image=None, seed=None):\n\
    # If no changes needed, return original\n\
    if not prompt and not reference_image and not seed:\n\
        return workflow_json\n\
    \n\
    # Make a copy to avoid modifying the original\n\
    workflow = json.loads(json.dumps(workflow_json))\n\
    \n\
    # Update reference image if provided\n\
    if reference_image:\n\
        for node_id, node in workflow.items():\n\
            if node.get("class_type") == "LoadImage":\n\
                node["inputs"]["image"] = reference_image\n\
    \n\
    # Update prompt if provided\n\
    if prompt:\n\
        for node_id, node in workflow.items():\n\
            if node.get("class_type") == "CLIPTextEncode":\n\
                node["inputs"]["text"] = prompt\n\
    \n\
    # Update seed if provided, otherwise generate a random one\n\
    if seed is None:\n\
        seed = random.randint(1, 999999999999999)\n\
        \n\
    for node_id, node in workflow.items():\n\
        if node.get("class_type") == "RandomNoise":\n\
            node["inputs"]["noise_seed"] = seed\n\
    \n\
    return workflow\n\
\n\
# Run the ComfyUI workflow\n\
def run_workflow(workflow_json, reference_image=None, prompt=None, seed=None):\n\
    prompt_url = "http://127.0.0.1:8188/prompt"\n\
    \n\
    # Convert to API format if it\'s in UI format\n\
    api_workflow = convert_ui_to_api_format(workflow_json)\n\
    \n\
    # Update with prompt and reference image if provided\n\
    api_workflow = update_workflow_with_prompt_and_image(api_workflow, prompt, reference_image, seed)\n\
    \n\
    # Queue the prompt\n\
    p = {"prompt": api_workflow}\n\
    data = json.dumps(p)\n\
    response = requests.post(prompt_url, data=data)\n\
    \n\
    # Check for errors in the response\n\
    if response.status_code != 200:\n\
        print(f"Error from ComfyUI API: {response.text}")\n\
        return None\n\
    \n\
    prompt_id = response.json().get("prompt_id")\n\
    if not prompt_id:\n\
        print("No prompt_id returned from ComfyUI")\n\
        return None\n\
    \n\
    print(f"Prompt ID: {prompt_id}")\n\
    \n\
    # Wait for the job to complete\n\
    output_images = []\n\
    max_wait_time = 300  # 5 minutes timeout\n\
    start_time = time.time()\n\
    \n\
    while True:\n\
        if time.time() - start_time > max_wait_time:\n\
            print("Timeout waiting for ComfyUI to process the workflow")\n\
            break\n\
            \n\
        time.sleep(1)\n\
        history_url = f"http://127.0.0.1:8188/history/{prompt_id}"\n\
        response = requests.get(history_url)\n\
        \n\
        if response.status_code == 200:\n\
            history = response.json()\n\
            if history.get(prompt_id, {}).get("outputs"):\n\
                outputs = history[prompt_id]["outputs"]\n\
                for node_id, node_output in outputs.items():\n\
                    if "images" in node_output:\n\
                        for image_data in node_output["images"]:\n\
                            # Convert image filename to base64\n\
                            image_path = f"/comfyui/output/{image_data.get(\'filename\', \'\')}" \n\
                            if os.path.exists(image_path):\n\
                                with open(image_path, "rb") as f:\n\
                                    image_bytes = f.read()\n\
                                    output_images.append({\n\
                                        "image": base64.b64encode(image_bytes).decode("utf-8"),\n\
                                        "type": image_data.get("type", "output"),\n\
                                        "filename": image_data.get("filename", "")\n\
                                    })\n\
                print(f"Generation complete, found {len(output_images)} images")\n\
                break\n\
    \n\
    return output_images\n\
\n\
# Handler for RunPod\n\
def handler(event):\n\
    # Extract inputs\n\
    job_input = event.get("input", {})\n\
    \n\
    # Check for simple mode (just prompt and reference image)\n\
    prompt = job_input.get("prompt")\n\
    reference_image_b64 = job_input.get("reference_image")\n\
    seed = job_input.get("seed")\n\
    \n\
    # Save the reference image if provided\n\
    reference_image_filename = None\n\
    if reference_image_b64:\n\
        reference_image_filename = save_image_from_base64(reference_image_b64)\n\
    \n\
    # Get the workflow - either from input or use default\n\
    workflow_data = job_input.get("workflow")\n\
    if workflow_data:\n\
        # Parse the workflow data\n\
        try:\n\
            # Handle both string JSON and dictionary inputs\n\
            workflow_json = json.loads(workflow_data) if isinstance(workflow_data, str) else workflow_data\n\
            \n\
            # Log workflow type for debugging\n\
            if "nodes" in workflow_json:\n\
                print("Detected UI workflow format - will convert to API format")\n\
            else:\n\
                print("Detected API workflow format")\n\
        except json.JSONDecodeError:\n\
            return {"error": "Invalid workflow JSON"}\n\
    else:\n\
        # Use default workflow if none provided but prompt or reference image is given\n\
        if prompt or reference_image_b64:\n\
            print("Using default workflow with provided prompt/reference image")\n\
            workflow_json = load_default_workflow()\n\
        else:\n\
            return {"error": "Either workflow or prompt/reference image must be provided"}\n\
    \n\
    # Run the workflow\n\
    output_images = run_workflow(workflow_json, reference_image_filename, prompt, seed)\n\
    \n\
    if not output_images:\n\
        return {"error": "Failed to generate images"}\n\
    \n\
    return {"images": output_images}\n\
\n\
# Start ComfyUI when the container starts\n\
if __name__ == "__main__":\n\
    if not start_comfyui():\n\
        print("Failed to start ComfyUI. Exiting.")\n\
        exit(1)\n\
    \n\
    print("Starting RunPod handler...")\n\
    runpod.serverless.start({\'handler\': handler})\n\
' > /comfyui/runpod_handler.py && chmod +x /comfyui/runpod_handler.py

# Set the entrypoint
ENTRYPOINT ["python", "/comfyui/runpod_handler.py"] 