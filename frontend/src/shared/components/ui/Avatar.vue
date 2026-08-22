<template>
  <div :style="boxStyle">{{ initials }}</div>
</template>

<script setup>
import { computed } from "vue";

const props = defineProps({
  name: { type: String, default: "" },
  size: { type: Number, default: 32 },
  gradient: { type: String, default: "peach-amber" },
  customColor: { type: String, default: null },
  styleProp: { type: Object, default: () => ({}) }
});

function getInitials(name = "") {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

const initials = computed(() => getInitials(props.name));

const boxStyle = computed(() => {
  const bg = props.customColor
    ? props.customColor
    : props.gradient === "peach-amber"
      ? "linear-gradient(135deg, #FCD9B6, #F59E0B)"
      : "linear-gradient(135deg, #E8E5DD, #D4D0C5)";
  return {
    width: props.size + "px",
    height: props.size + "px",
    borderRadius: "999px",
    background: bg,
    color: "white",
    display: "grid",
    placeItems: "center",
    fontWeight: 600,
    fontSize: Math.max(10, props.size * 0.36) + "px",
    flexShrink: 0,
    ...props.styleProp
  };
});
</script>
