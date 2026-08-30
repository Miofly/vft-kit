# AI Studio Task Operations

Read this reference for model-pipeline jobs, script-task projects, or Notebook background tasks.

Official references:

- Model-pipeline jobs through AI Studio CLI: <https://ai.baidu.com/ai-doc/AISTUDIO/lluckgp2n>
- Script tasks: <https://ai.baidu.com/ai-doc/AISTUDIO/Ik3e3g4lt>
- BML Codelab background tasks: <https://ai.baidu.com/ai-doc/AISTUDIO/Gktuwqf1x#%E4%BB%BB%E5%8A%A1>
- Classic Notebook background tasks: <https://ai.baidu.com/ai-doc/AISTUDIO/sk3e2z8sb#%E5%90%8E%E5%8F%B0%E4%BB%BB%E5%8A%A1>
- Notebook projects: <https://ai.baidu.com/ai-doc/AISTUDIO/Dk3e2vxg9>
- Project lifecycle: <https://ai.baidu.com/ai-doc/AISTUDIO/0k3e2tfzm>
- Compute cards: <https://ai.baidu.com/ai-doc/AISTUDIO/nk39v9kec>

The task pages were last marked as updated in 2024. Treat their lifecycle and limits as guidance, but re-read the live form for hardware, availability, rate, balance, and terms before every submission. The CLI examples below were also checked against `aistudio-sdk==0.3.9`; run the current command's `--help` before relying on an option.

Back up important code, checkpoints, and final outputs outside AI Studio. The project overview warns that a non-public project not run for 180 consecutive days may be permanently cleaned up.

## Choose the task type

Use a **model-pipeline job** for local or Notebook-tested command-line code submitted through `aistudio submit job`. Version 0.3.9 supports V100 pipelines with one, four, or eight GPUs.

Use a **script-task project** for the older web project type driven by a command such as `python train.py` or `bash run.sh`. It has its own files, datasets, launch command, versions, and task history.

Use a **Notebook background task** when the work already lives in a Notebook project and must outlive the interactive Notebook session. It submits an `.ipynb` from a saved project version to a separate GPU worker. The interactive Notebook may be running on CPU; that does not make the background task free.

For every type, debug the smallest representative run in an interactive Notebook first. Do not spend task compute on dependency discovery or syntax errors that CPU can expose.

## Model-pipeline CLI job

Install the current `aistudio-sdk` in an isolated tool environment. The official setup command is `aistudio config --token <token>`, but it places the token in process arguments. Never put a literal token in a tool call, shell history, logs, or chat. Reuse an already configured credential, ask the user to configure it outside the agent, or use an approved private wrapper that writes the official token file with mode `0600`.

Before use, inspect the current interface:

```bash
aistudio --help
aistudio submit job --help
aistudio jobs --help
aistudio stop job --help
aistudio job --help
```

Prepare one code directory no larger than 50 MB with an explicit entry command. Mounted datasets appear under `/home/aistudio/data/`; only `/home/aistudio/output/` persists. The official page allows at most three mounted datasets and caps output at 100 GB or 10,000 files.

After checking the live resource and payment details, require explicit cost confirmation, then submit with every cost-sensitive default made explicit:

```bash
aistudio submit job \
  --name NAME \
  --path /ABSOLUTE/CODE_DIR \
  --cmd 'bash run.sh' \
  --env CURRENT_ENV \
  --device v100 \
  --gpus 1 \
  --payment coupon \
  --mount_dataset DATASET_ID
```

Version 0.3.9 defaults to `acoin`; never omit `--payment`. The environment names and V100-only device list can change, so choose only values printed by the current `--help` and supported by the live account.
Omit `--mount_dataset` when no dataset is needed.

Capture the returned `pipeline_id`, initial `status`, creation time, and detail `url`. Query before retrying an ambiguous submission:

```bash
aistudio jobs PIPELINE_ID
```

The current CLI can stop an exact pipeline. Omit `--force` so its confirmation remains active:

```bash
aistudio stop job PIPELINE_ID
```

The official article routes live log monitoring through the returned model-pipeline URL. Do not invent a CLI log command. Once the query or detail page exposes the actual `job_id`, list and copy exact output files:

```bash
aistudio job JOB_ID ls
aistudio job JOB_ID cp RESULT_FILE /ABSOLUTE/LOCAL_PATH
```

Verify downloaded size and task-specific content. Do not confuse `pipeline_id` with `job_id`.

## Script-task project

1. Reuse the authenticated browser session and create or open a script-task project. Verify the project ID and intended files before editing.
2. Add only task-owned code and licensed datasets. The 2024 document lists a 1 GB per-file upload limit, 10 files per upload, 2 GB total project-file limit, and 1 MB preview limit; verify current UI limits.
3. Mark the intended entry file when the UI requires it and set an explicit launch command. Avoid shell interpolation of secrets; load secrets from the runtime mechanism approved for the task.
4. Read datasets beneath `/root/paddlejob/workspace/train_data/datasets/`. Write downloadable results beneath `/root/paddlejob/workspace/output/` (`./output` in the project view).
5. Save all changes and add a useful task note. Before clicking submit, inspect the current hardware, availability, rate, balance, launch command, files, and datasets. Require explicit confirmation of the displayed cost.
6. Submit once, capture the task ID, and verify the history row. A timeout or missing toast has unknown outcome: inspect history before retrying.
7. Poll the task state and logs. On success, download the output archive and verify expected files, sizes, and task-specific checks. On failure, preserve the log and report its final error. Terminate only the exact queued/running task intended by the user.

The official page documents a 72-hour runtime ceiling and failure when output exceeds 20 GB or 10,000 files. Keep checkpoints sparse and delete disposable intermediates during training. Its P40/V100 examples and rates are historical; never use them as current availability or price.

## Notebook background task

1. Open the intended Notebook and read `references/notebook.md`. Keep the executable `.ipynb` in the project root (`/home/aistudio/`) and include it explicitly in the saved version; BML Codelab will not create a background task without it.
2. Run and validate the Notebook interactively, then save a new version containing all required code and small support files. Version creation is the task snapshot; later draft edits do not change the submitted task.
3. Open `任务` -> `创建任务`, choose the version and executable Notebook, and add a useful note.
4. Inspect the live GPU environment, availability, rate, balance, and task summary. Require explicit confirmation of the displayed cost before submission, even when the current interactive Notebook is CPU or free.
5. Submit once, capture the task ID, and verify its state. A queued task may remain queued for up to 24 hours according to the official document and does not consume compute while queued.
6. After successful submission, stop the interactive Notebook runtime unless still needed. The background task is independent of that runtime.
7. Poll state and logs. The user can terminate an exact queued or running task. Do not leave a task unobserved when the request requires completion.
8. On success, download locally or import the output archive into `/home/aistudio/<task-id>/`, then verify expected outputs. Delete a completed task only with explicit authorization and only after output verification.

The official document says only the latest five tasks are retained, task outputs are retained for up to 30 days, runtime is capped at 72 hours excluding queue time, and output over 20 GB or 10,000 files fails. Import to project space is unavailable when that space exceeds 60 GB. Recheck these limits in the live UI.

## Completion report

Report the project, pipeline, and task IDs as applicable; task type; selected hardware and confirmed rate/payment; submitted version or launch command; terminal state; elapsed time; output location and verification; remaining running or queued tasks; and whether the interactive Notebook runtime was stopped. Separate platform-confirmed facts from assumptions and stale documentation examples.
