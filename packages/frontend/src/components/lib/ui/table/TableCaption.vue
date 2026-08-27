<script setup lang="ts">
import { cn } from '@/lib/utils';
import { useAttrs } from 'vue';

const attrs = useAttrs();
</script>

<template>
  <caption :class="cn('text-muted-foreground mt-4 text-sm', attrs.class as string)">
    <slot />
  </caption>
</template>
