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
# Version bump procedure: update the tag below (check storage-format
# compatibility notes at https://github.com/qdrant/qdrant/releases),
# then publish via the workflow. The existing named volume
# (monadic-chat-qdrant-data) is reused across versions; qdrant migrates
# storage forward automatically but not backward — do not downgrade.
FROM qdrant/qdrant:v1.18.2

ARG PROJECT_TAG=monadic-chat
LABEL project=${PROJECT_TAG}
