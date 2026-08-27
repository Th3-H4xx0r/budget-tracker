<script setup lang="ts">
import { cn } from '@/lib/utils';
import { useAttrs } from 'vue';

const attrs = useAttrs();
</script>

<template>
  <tfoot :class="cn('bg-muted/50 border-t font-medium [&>tr]:last:border-b-0', attrs.class as string)">
    <slot />
  </tfoot>
</template>
