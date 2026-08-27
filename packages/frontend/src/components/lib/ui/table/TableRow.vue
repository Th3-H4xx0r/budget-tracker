<script setup lang="ts">
import { cn } from '@/lib/utils';
import { useAttrs } from 'vue';

const attrs = useAttrs();
</script>

<template>
  <tr :class="cn('hover:bg-muted/50 data-[state=selected]:bg-muted border-b transition-colors', attrs.class as string)">
    <slot />
  </tr>
</template>
