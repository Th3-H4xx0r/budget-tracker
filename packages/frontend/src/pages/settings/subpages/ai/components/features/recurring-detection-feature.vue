<template>
  <div v-if="isLoadingModels" class="text-muted-foreground flex items-center gap-2 py-4 text-sm">
    <Loader2Icon class="size-4 animate-spin" />
    {{ $t('settings.ai.recurringDetection.loading') }}
  </div>

  <ModelSelectorCard
    v-else
    :feature-status="featureStatus"
    :grouped-models="groupedModels"
    :available-models="availableModels"
    :default-open="defaultOpen"
  />
</template>

<script setup lang="ts">
import { useFeatureModels } from '@/composable/data-queries/use-feature-models';
import { AIFeatureStatus, AI_FEATURE } from '@bt/shared/types';
import { Loader2Icon } from '@lucide/vue';

import ModelSelectorCard from '../shared/model-selector-card.vue';

defineProps<{ featureStatus: AIFeatureStatus; defaultOpen?: boolean }>();

const { availableModels, groupedModels, isLoading: isLoadingModels } = useFeatureModels(AI_FEATURE.recurringDetection);
</script>
