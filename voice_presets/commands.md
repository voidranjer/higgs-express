# Commands

## Docker run command

```shell
docker run --gpus all --ipc=host --shm-size=20gb --network=host --volume /root/higgs_audio_v2:/opt/voice_presets --name higgs bosonai/higgs-audio-vllm:latest --served-model-name "higgs-audio-v2-generation-3B-base" --model "bosonai/higgs-audio-v2-generation-3B-base"  --audio-tokenizer-type "bosonai/higgs-audio-v2-tokenizer" --limit-mm-per-prompt audio=50 --max-model-len 8192 --port 8000 --gpu-memory-utilization 0.8 --disable-mm-preprocessor-cache --voice-presets-dir "/opt/voice_presets"
```

> After the container has stopped, the container image persists on your system (you can run out of storage very quickly). To reuse the same container, use `docker start higgs` and `docker exec -it higgs /bin/bash` to get a shell inside the container. To remove the container, use `docker rm -f higgs`.

## Curl sanity test

```shell
curl -X POST "http://localhost:8000/v1/audio/speech" \
				 -H "Content-Type: application/json" \
				 -d '{
               "model": "higgs-audio-v2-generation-3B-base",
               "voice": "luthen",
               "input": "Are you sure you want to do this?",
               "response_format": "pcm"
			 }' \
				 --output - | ffmpeg -f s16le -ar 24000 -ac 1 -i - speech.wav
```
