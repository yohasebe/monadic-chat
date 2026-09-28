# Pinned mirror of the upstream Qdrant image, republished to ghcr.io by
# .github/workflows/publish-images.yml as monadic-qdrant. Pinning serves
# two purposes:
#   1. Reproducibility — upstream `qdrant/qdrant:latest` is mutable; an
#      upstream-breaking change must never reach users outside a Monadic
#      Chat release.
#   2. Registry unification — all runtime-pulled images come from
#      ghcr.io/yohasebe/* with the same tag policy (latest/dev/<version>,
#      user-selectable via MONADIC_IMAGE_TAG), and user machines never
#      hit Docker Hub anonymous-pull rate limits at install time.
#
# Version bump procedure: update the tag and the index digest below
# (check storage-format compatibility notes at
# https://github.com/qdrant/qdrant/releases; read the digest with
# `docker buildx imagetools inspect qdrant/qdrant:<tag>`), then publish via
# the workflow. The digest keeps a re-pushed upstream tag from changing
# what this Dockerfile publishes. The existing named volume
# (monadic-chat-qdrant-data) is reused across versions; qdrant migrates
# storage forward automatically but not backward — do not downgrade.
FROM qdrant/qdrant:v1.19.1@sha256:12364fe851b9f17356fc88189fc06d1b521262e04659ec7345975b00c9246a10

ARG PROJECT_TAG=monadic-chat
LABEL project=${PROJECT_TAG}
