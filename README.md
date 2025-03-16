# PuLID FLUX Serverless API on RunPod

This repository contains the necessary files to deploy a PuLID FLUX API endpoint on RunPod Serverless. It allows you to use the powerful FLUX.1 AI model with PuLID (Personalized User Latent Image Direction) to generate images with face swapping capabilities.

## Features

- Ready-to-deploy Docker image for RunPod Serverless
- ComfyUI workflow integration with PuLID FLUX
- API endpoint for text-to-image generation with face swap functionality
- Includes all necessary models and components:
  - FLUX.1-dev GGUF model
  - PuLID FLUX models
  - EVA CLIP model
  - InsightFace models
  - Additional LoRAs for better results

## Deployment Instructions

### 1. Deploy on RunPod Serverless

1. Go to [RunPod Console](https://www.runpod.io/console/serverless)
2. Click "New Endpoint"
3. Configure your endpoint:
   - Endpoint Name: `pulid-flux-api` (or any name you prefer)
   - Worker Config:
     - Select GitHub repository: `https://github.com/jd316/pulid-flux-rupod-serverless`
     - Branch: `master`
     - Dockerfile Path: `/Dockerfile`
   - Container Settings:
     - GPU Count: 1
     - Container Disk: At least 50GB
     - Expose HTTP Port: 8188
   - Advanced Settings:
     - Active Workers: 1
     - Max Workers: 3 (adjust as needed)
     - Idle Timeout: 5 seconds
     - Execution Timeout: 600 seconds

4. Click "Deploy"

### 2. Using Your Endpoint

Once deployed, you can send requests to your endpoint using the RunPod API.

## Technical Details

This repository uses a specialized Dockerfile that's optimized for RunPod serverless deployment:

- **No Git Dependencies**: Rather than using `git clone` operations which can fail in isolated build environments, the Dockerfile downloads repository ZIP archives directly.
- **Custom Nodes**: All required ComfyUI custom nodes (GGUF-Loader, PuLID FLUX, rgthree-comfy, and Custom-Scripts) are installed automatically.
- **Model Downloads**: All necessary AI models are downloaded during the build process.
- **API Handler**: Includes a Python handler that interfaces between RunPod's API and ComfyUI's internal API.

## API Usage

The API endpoint accepts the following parameters:

```json
{
  "input": {
    "prompt": "Your text prompt here",
    "reference_image": "base64 encoded image for face swap",
    "seed": 123456789 (optional)
  }
}
```

### Example Request

```python
import requests
import base64
import json

# Your RunPod API key and endpoint ID
API_KEY = "your_runpod_api_key"
ENDPOINT_ID = "your_endpoint_id"

# Load reference image
with open("reference_face.jpg", "rb") as f:
    reference_image = base64.b64encode(f.read()).decode("utf-8")

# Prepare payload
payload = {
    "input": {
        "prompt": "photo of a beautiful woman, 8k, highly detailed",
        "reference_image": reference_image,
        "seed": 123456789
    }
}

# API request URL
url = f"https://api.runpod.ai/v2/{ENDPOINT_ID}/runsync"

# Send request
response = requests.post(
    url,
    headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {API_KEY}"
    },
    json=payload
)

# Process response
if response.status_code == 200:
    data = response.json()
    # Save the generated image
    if "images" in data["output"]:
        for i, img_data in enumerate(data["output"]["images"]):
            img_bytes = base64.b64decode(img_data["image"])
            with open(f"generated_image_{i}.png", "wb") as f:
                f.write(img_bytes)
            print(f"Saved generated_image_{i}.png")
else:
    print(f"Error: {response.text}")
```

## Advanced Configuration

You can also provide a custom ComfyUI workflow in your API request:

```json
{
  "input": {
    "workflow": "your ComfyUI workflow JSON",
    "reference_image": "base64 encoded image",
    "prompt": "text prompt"
  }
}
```

The API supports both UI and API workflow formats from ComfyUI and will automatically convert between them as needed.

## Troubleshooting

- **Timeout errors**: Increase the execution timeout in your endpoint settings
- **Out of memory**: Make sure you've allocated enough GPU resources 
- **Build failures**: 
  - The NSFW_master.safetensors URL in the Dockerfile has a limited lifespan. If building fails, you may need to update it with a new URL
  - If you experience network connectivity issues during build, the Dockerfile is designed to avoid Git operations which can be problematic in some environments

## License

This project uses several AI models and code components with their own respective licenses:

- FLUX.1: [Black Forest Labs License](https://huggingface.co/black-forest-labs/FLUX.1-dev)
- ComfyUI: [GPL-3.0 License](https://github.com/comfyanonymous/ComfyUI)
- PuLID FLUX: [License](https://huggingface.co/aloneill/pulid_flux)

## Acknowledgements

- Original ComfyUI by [comfyanonymous](https://github.com/comfyanonymous/ComfyUI)
- FLUX model by [Black Forest Labs](https://huggingface.co/black-forest-labs)
- PuLID FLUX workflow from [The Future Thinker](https://thefuturethinker.org)
- RunPod for the serverless platform
