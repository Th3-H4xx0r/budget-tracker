<script setup lang="ts">
import { cn } from '@/lib/utils';
import { useAttrs } from 'vue';

const attrs = useAttrs();
</script>

<template>
  <thead :class="cn('[&_tr]:border-b', attrs.class as string)">
    <slot />
  </thead>
</template>
