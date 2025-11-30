#!/bin/bash
# Quick unlock script
LOCK_UUID="b5794fb1-be4e-70d3-6cc4-bb21c561add9"
echo "Releasing lock: $LOCK_UUID"
terraform force-unlock -force "$LOCK_UUID"
echo "✅ Done!"
